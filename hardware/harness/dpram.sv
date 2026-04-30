// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       dpram.sv
\brief      Dual-Port RAM (simulation model + vendor-backed instantiation)

\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  Educational dual-port RAM. It supports:

  - RTL implementation: a simple behavioral true dual-port RAM is used to mimic
    a real dual-port memory. In simulation, the full memory array is exposed at the top
    SystemVerilog level (`mem_o`) for direct access from C++ testbenches
    (DPI / Verilator). This model favors clarity and simulation speed over strict
    hardware semantics and may exhibit multi-driver behavior in corner cases,
    so it is not suitable for synthesis.

  - MPFS Discovery Kit implementation: this module instantiates either
    `dpram_64w.sv` or `dpram_32w.sv` to build a dual-port RAM from Microchip IPs,
    depending on `DataWidth`.

\section dpram_scope Scope and limitations
  - No collision handling is enforced between ports in the simulation variant; the
    vendor-backed variant should be used for implementation on FPGA.
  - Read and write latency is one cycle by default bu can be randomized using `NoPerfectMemory`.
  - Byte-enable writes are supported on both ports.

\remarks
  - TODO: .

\section dpram_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version of the module.            |
********************************************************************************
*/

module dpram

  import target_pkg::TARGET_RTL;
  import target_pkg::TARGET_MPFS_DISCOVERY_KIT;
  import target_pkg::TARGET_CORA_Z7_07S;

#(
    /// Implementation target
    parameter int unsigned Target     = TARGET_RTL,
    /// Use non-perfect memory
    parameter bit          NoPerfectMemory = 0,
    /// Number of bits in a byte
    parameter int unsigned ByteLength = 8,
    /// Data bus width in bits (applies to core and AXI)
    parameter int unsigned DataWidth  = 32,
    /// Byte-Enable width
    parameter int unsigned BeWidth    = DataWidth / ByteLength,
    /// Number of `DataWidth` word storable in the RAM.
    parameter int unsigned Depth      = 1280,
    /// Address bus width in bits (applies to core and AXI)
    parameter int unsigned AddrWidth  = $clog2(Depth)

) (
`ifdef SIM
    /// (Simulation only) Exposes the RAM contents for testbenches
    output logic [      DataWidth-1:0] mem_o     [Depth],
`endif
    /// Port A clock
    input  logic                       a_clk_i,
    /// Port A address (word address in the 64-bit logical space)
    input  logic [AddrWidth   - 1 : 0] a_addr_i,
    /// Port A write data (64-bit)
    input  logic [DataWidth   - 1 : 0] a_wdata_i,
    /// Port A byte-enable (one bit per byte; 8 bits for 64-bit data)
    input  logic [DataWidth/8 - 1 : 0] a_be_i,
    /// Port A write enable (1 = write)
    input  logic                       a_wren_i,
    /// Port A read enable  (1 = read)
    input  logic                       a_rden_i,
    /// Port A read data (registered, 1-cycle latency)
    output logic [DataWidth   - 1 : 0] a_rdata_o,
    /// Grant: Ready to accept address transfert
    output logic                       a_gnt_o,
    /// Response transfer valid
    output logic                       a_rvalid_o,
    /// Error response
    output logic                       a_err_o,
    /// Port B clock
    input  logic                       b_clk_i,
    /// Port B address (word address in the 64-bit logical space)
    input  logic [AddrWidth   - 1 : 0] b_addr_i,
    /// Port B write data (64-bit)
    input  logic [DataWidth   - 1 : 0] b_wdata_i,
    /// Port B byte-enable (one bit per byte; 8 bits for 64-bit data)
    input  logic [DataWidth/8 - 1 : 0] b_be_i,
    /// Port B write enable (1 = write)
    input  logic                       b_wren_i,
    /// Port B read enable  (1 = read)
    input  logic                       b_rden_i,
    /// Port B read data (registered, 1-cycle latency)
    output logic [DataWidth   - 1 : 0] b_rdata_o,
    /// Grant: Ready to accept address transfert
    output logic                       b_gnt_o,
    /// Response transfer valid
    output logic                       b_rvalid_o,
    /// Error response
    output logic                       b_err_o
);

  /// Port A request accept
  assign a_gnt_o    = a_wren_i || a_rden_i;
  /// Port A request response (completion)
  assign a_rvalid_o = a_wren_i || a_rden_i;
  /// Port A error flag
  assign a_err_o    = 1'b0;

  /// Port B request accept
  assign b_gnt_o    = b_wren_i || b_rden_i;
  /// Port B error flag
  assign b_err_o    = 1'b0;

  generate

    /// Core-side memory hit signal.
    /*!
    * Since the dual-port RAM provides single-cycle access and is always available,
    * the `b_rvalid_o` signal can directly reflect the validity of the core's request.
    *
    * - If either a read or a write is requested (`b_rden_i`, `b_wren_i`),
    *   the memory is assumed to complete the operation without wait states.
    *
    * This simplifies handshaking by eliminating the need for an explicit memory
    * ready/acknowledge protocol.
    *
    * For non-perfect memory test, a latency is added to `b_rvalid_o` to emulate
    * a memory latency (even if the data is ready, the core will not capture it if
    * the rvalid signal is not asserted).
    * The latency depends on the address. This ensure a non-constant latency.
    */
    if (NoPerfectMemory) begin : gen_not_perfect_memory

      localparam int unsigned MAX_LAT = 3;  // 0..MAX_LAT
      localparam int unsigned ADDR_LAT_LSB = (DataWidth == 64) ? 3 : 2;

      localparam int unsigned LAT_W = (MAX_LAT < 1) ? 1 : $clog2(MAX_LAT + 1);
      localparam int unsigned LAT_MAX_REPR = (1 << LAT_W) - 1;
      localparam bit NEED_CLAMP = (MAX_LAT != LAT_MAX_REPR);

      logic             req_now;
      logic             busy_q;
      logic [LAT_W-1:0] wait_q;
      logic [LAT_W-1:0] lat_raw;
      logic [LAT_W-1:0] lat_sel;

      assign req_now = b_wren_i || b_rden_i;

      // Derive a deterministic latency from address bits (ignore alignment by default).
      // Uses bits [ADDR_LAT_LSB + LAT_W - 1 : ADDR_LAT_LSB].
      assign lat_raw = b_addr_i[ADDR_LAT_LSB+:LAT_W];

      if (NEED_CLAMP) begin : gen_clamp
        // Clamp to MAX_LAT to keep latency in 0..MAX_LAT without using modulo.
        assign lat_sel = (lat_raw > MAX_LAT[LAT_W-1:0]) ? MAX_LAT[LAT_W-1:0] : lat_raw;
      end
      else begin : gen_noclamp
        assign lat_sel = lat_raw;
      end

      // Hit is high when the request is active and the wait counter reached zero.
      // Deasserts combinationally when req_now drops.
      assign b_rvalid_o = req_now && busy_q && (wait_q == '0);

      always_ff @(posedge b_clk_i) begin
        if (!busy_q) begin
          if (req_now) begin
            busy_q <= 1'b1;
            wait_q <= (MAX_LAT == 0) ? '0 : lat_sel;  // sample latency at request start
          end
        end
        else begin
          if (!req_now) begin
            busy_q <= 1'b0;
            wait_q <= '0;
          end
          else if (wait_q != '0) begin
            wait_q <= wait_q - 1'b1;
          end
        end
      end
    end
    else begin : gen_perfect_memory
      assign b_rvalid_o = b_wren_i || b_rden_i;
    end


    if (Target == TARGET_RTL) begin : gen_rtl
      /******************** DECLARATION ********************/
      /* parameters verification */

      /* local parameters */

      /* machine states */

      /* functions */

      /* wires */

      /* registers */
      /// Registered read address for port A (held when `a_rden_i`=`0`)
      reg   [AddrWidth -1:0] a_addr_i_q;
      /// Registered read address for port B (held when `b_rden_i`=`0`)
      reg   [AddrWidth -1:0] b_addr_i_q;
      /* verilator lint_off MULTIDRIVEN */
      /// memory array
      logic [ DataWidth-1:0] mem        [Depth];
      /* verilator lint_on MULTIDRIVEN */

      /********************             ********************/

      /// Port A memory access logic.
      /*!
      * - Writes: per-byte using `a_be_i`; active when `a_wren_i`=`1`.
      * - Reads : capture address when `a_rden_i`=`1`; output is `mem[a_addr_i_q]`.
      */
      always_ff @(posedge a_clk_i) begin : port_a_ctrl
        if (a_wren_i) begin
          for (int i = 0; i < BeWidth; i++) begin
            if (a_be_i[i])
              mem[a_addr_i][i*ByteLength+:ByteLength] <= a_wdata_i[i*ByteLength+:ByteLength];
          end
        end
        else if (a_rden_i) begin
          a_addr_i_q <= a_addr_i;
        end
      end

      /// Output driven by port_a_ctrl
      assign a_rdata_o = mem[a_addr_i_q];

      /// Port B memory access logic.
      /*!
      * - Writes: per-byte using `b_be_i`; active when `b_wren_i`=`1`.
      * - Reads : capture address when `b_rden_i`=`1`; output is `mem[b_addr_i_q]`.
      */
      always_ff @(posedge b_clk_i) begin : port_b_ctrl
        if (b_wren_i) begin
          for (int i = 0; i < BeWidth; i++) begin
            if (b_be_i[i])
              mem[b_addr_i][i*ByteLength+:ByteLength] <= b_wdata_i[i*ByteLength+:ByteLength];
          end
        end
        else if (b_rden_i) begin
          b_addr_i_q <= b_addr_i;
        end
      end

      /// Output driven by port_a_ctrl
      assign b_rdata_o = mem[b_addr_i_q];

`ifdef SIM
      /// memory exposure for simulation (DPI/Verilator access).
      assign mem_o = mem;
`endif

    end
    else if (Target == TARGET_MPFS_DISCOVERY_KIT) begin : gen_mpfs_dsco_kit
      /// MPFS DISCOVERY KIT memory generation
      /*!
      * This block generates either a 32-bit or a 64-bit Depth
      * memory depending on `DataWidth`.
      * To generate the a 32-bit memory, the `dpram_32w` module
      * is instanciated.
      * To generate the a 64-bit memory, the `dpram_64w` module
      * is instanciated.
      * Both use Microchip BRAM from MPFS DISCOVERY KIT.
      */
      if (DataWidth == 32) begin : gen_32
        dpram_32w #(
            .Depth(Depth)
        ) ram (
            .a_clk_i  (a_clk_i),
            .a_addr_i (a_addr_i),
            .a_wdata_i(a_wdata_i),
            .a_be_i   (a_be_i),
            .a_wren_i (a_wren_i),
            .a_rden_i (a_rden_i),
            .a_rdata_o(a_rdata_o),
            .b_clk_i  (b_clk_i),
            .b_addr_i (b_addr_i),
            .b_wdata_i(b_wdata_i),
            .b_be_i   (b_be_i),
            .b_wren_i (b_wren_i),
            .b_rden_i (b_rden_i),
            .b_rdata_o(b_rdata_o)
        );
      end
      else begin : gen_64
        dpram_64w #(
            .Depth(Depth)
        ) ram (
            .a_clk_i  (a_clk_i),
            .a_addr_i (a_addr_i),
            .a_wdata_i(a_wdata_i),
            .a_be_i   (a_be_i),
            .a_wren_i (a_wren_i),
            .a_rden_i (a_rden_i),
            .a_rdata_o(a_rdata_o),
            .b_clk_i  (b_clk_i),
            .b_addr_i (b_addr_i),
            .b_wdata_i(b_wdata_i),
            .b_be_i   (b_be_i),
            .b_wren_i (b_wren_i),
            .b_rden_i (b_rden_i),
            .b_rdata_o(b_rdata_o)
        );
      end

    end
    else if (Target == TARGET_CORA_Z7_07S) begin : gen_cora_z7_07s
      $fatal("FATAL ERROR: Cora z7-07s not supported yet.");

      /// Cora z7-07s memory generation
      /*!
      * This block generates either a 32-bit or a 64-bit Depth
      * memory depending on `DataWidth`.
      * To generate the a 32-bit memory, the `dpram_32w` module
      * is instanciated.
      * To generate the a 64-bit memory, the `dpram_64w` module
      * is instanciated.
      */
      // if (DataWidth == 32) begin : gen_32
      //   dpram32 #() dpram_32w (
      //       .clka (a_clk_i),
      //       .ena  (a_wren_i | a_rden_i),
      //       .wea  (a_be_i),
      //       .addra(a_addr_i),
      //       .dina (a_wdata_i),
      //       .douta(a_rdata_o),

      //       .clkb (b_clk_i),
      //       .enb  (b_wren_i | b_rden_i),
      //       .web  (b_be_i),
      //       .addrb(b_addr_i),
      //       .dinb (b_wdata_i),
      //       .doutb(b_rdata_o)
      //   );
      // end
      // else begin : gen_64
      //   dpram64 #() dpram_64w (
      //       .clka (a_clk_i),
      //       .ena  (a_wren_i | a_rden_i),
      //       .wea  (a_be_i),
      //       .addra(a_addr_i),
      //       .dina (a_wdata_i),
      //       .douta(a_rdata_o),

      //       .clkb (b_clk_i),
      //       .enb  (b_wren_i | b_rden_i),
      //       .web  (b_be_i),
      //       .addrb(b_addr_i),
      //       .dinb (b_wdata_i),
      //       .doutb(b_rdata_o)
      //   );
      // end
    end
    else begin : gen_error
      $fatal("FATAL ERROR: Unknown target.");
    end

  endgenerate

endmodule
