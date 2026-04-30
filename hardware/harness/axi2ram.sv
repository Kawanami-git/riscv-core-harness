// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       axi2ram.sv
\brief      AXI4-to-RAM bridge

\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  This module implements a simplified AXI4 slave connected to an external RAM
  interface.

  It translates AXI write and read transactions into:
    - RAM address
    - RAM write data
    - RAM byte enables
    - RAM write enable
    - RAM read enable

  The write path is handled through three phases:
    - address capture
    - write data transfer
    - write response generation

  The read path captures the AXI read request and returns RAM data on the AXI
  read channel.

  This component is intended as a lightweight bridge for memory-mapped RAM
  access in the riscv-core-harness platform.

\remarks
  - This is a simplified AXI4 slave intended for basic RAM accesses.
  - Only a limited subset of AXI4 behavior is handled.
  - Reset only affects AXI control logic; RAM contents are not modified.
  - TODO: Completely handle the AXI4 protocol.

\section axi2ram_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version of the module.            |
********************************************************************************
*/

module axi2ram #(
    /// Number of bits in a byte
    parameter int          ByteLength = 8,
    /// Address width
    parameter int unsigned AddrWidth  = 32,
    /// Data width
    parameter int unsigned DataWidth  = 32,
    /// Number of byte-enable bits
    parameter int unsigned BeWidth    = DataWidth / ByteLength
) (
    /* Global signals */
    /// AXI domain clock (drives the AXI-side port of the RAM and AXI control)
    input  wire                                 axi_clk_i,
    /// Global active-low reset for AXI control logic (memory contents unchanged)
    input  wire                                 rstn_i,
    /// AXI4 slave interface
           axi_if.slave                         s_axi,
    /// RAM address
    output wire         [AddrWidth     - 1 : 0] ram_addr_o,
    /// RAM write data
    output wire         [DataWidth     - 1 : 0] ram_wdata_o,
    /// RAM byte enable
    output wire         [  BeWidth     - 1 : 0] ram_be_o,
    /// RAM write enable
    output wire                                 ram_wren_o,
    /// RAM read enable
    output wire                                 ram_rden_o,
    /// RAM read data
    input  wire         [DataWidth     - 1 : 0] ram_rdata_i
);

  /******************** DECLARATION ********************/
  /* parameters verification */

  /* local parameters */

  /* machine states */

  /// AXI write Finite State Machine states
  typedef enum reg [1:0] {
    /// No transaction
    WR_IDLE,
    /// Transaction in progress (write data beats)
    WR_BURST,
    /// Write response phase
    WR_RESP
  } write_states_e;
  /// AXI write Finite State Machine state register
  write_states_e write_state_d;

  /// AXI read Finite State Machine states
  typedef enum reg [0:0] {
    /// No transaction
    RD_IDLE,
    /// Transaction on going
    RD_BURST
  } read_states_e;
  /// AXI read Finite State Machine state register
  read_states_e                     read_state_d;

  /* functions */

  /* wires */
  /// Collect AXI fields intentionally unused by this simplified RAM slave
  wire                              unused_axi;

  /* registers */
  /// Registered AWID from AXI write address channel (transaction ID)
  reg           [            7 : 0] s_axi_awid_q;
  /// Registered write address from AXI master
  reg           [AddrWidth - 1 : 0] s_axi_awaddr_q;
  /// Indicates if the slave can accept a new write address
  reg                               s_axi_awready_q;
  /// Controls handshake with master for write data channel
  reg                               s_axi_wready_q;
  /// Stores the ID to return in write response
  reg           [            7 : 0] s_axi_bid_q;
  /// Response code for write transaction (OKAY, SLVERR, etc.)
  reg           [            1 : 0] s_axi_bresp_q;
  /// Controls handshake for write response channel
  reg                               s_axi_bvalid_q;
  /// Registered ARID from AXI read address channel (transaction ID)
  reg           [            7 : 0] s_axi_arid_q;
  /// Registered read address from AXI master
  reg           [AddrWidth - 1 : 0] s_axi_araddr_q;
  /// Registered burst length (number of data beats - 1)
  reg           [            7 : 0] s_axi_arlen_q;
  /// Registered size of each transfer in the burst (log2(bytes))
  reg           [            2 : 0] s_axi_arsize_q;
  /// Registered burst type (e.g., INCR, FIXED)
  reg           [            1 : 0] s_axi_arburst_q;
  /// Indicates if the slave can accept a new read address
  reg                               s_axi_arready_q;
  /// Response code for read transaction (OKAY, SLVERR, etc.)
  reg           [            1 : 0] s_axi_rresp_q;
  /// Indicates the last data beat in a burst
  reg                               s_axi_rlast_q;
  /// Indicates valid read data is available on the bus
  reg                               s_axi_rvalid_q;
  /********************             ********************/

  /// Collect AXI fields intentionally unused by this simplified RAM slave
  assign unused_axi = &{1'b0, s_axi.awlen, s_axi.awlock, s_axi.awcache, s_axi.awprot, s_axi.awsize,
                        s_axi.awburst, s_axi.arlock, s_axi.arcache, s_axi.arprot, 1'b0};

  /// AXI machine write FSM
  /*!
  * This finite state machine (FSM) handles the AXI write transaction flow.
  *
  * - WR_IDLE:      Waits for a valid AXI write address (`s_axi.awvalid`). Upon assertion,
  *                 it captures the write parameters and moves to WR_BURST.
  *
  * - WR_BURST:     Handles incoming write data beats. Transition to WR_RESP occurs
  *                 when the last write data beat (`s_axi.wlast`) is valid.
  *
  * - WR_RESP:      Sends the write response (`s_axi.bvalid`). Once the master acknowledges
  *                 by asserting `s_axi.bready`, the FSM returns to WR_IDLE.
  *
  * This ensures correct sequencing of the write address, data, and response phases.
  */
  always_ff @(posedge axi_clk_i) begin : axi_write_fsm
    if (!rstn_i) write_state_d <= WR_IDLE;
    else begin
      case (write_state_d)
        WR_IDLE:  if (s_axi.awvalid) write_state_d <= WR_BURST;
        WR_BURST: if (s_axi.wlast && s_axi.wvalid) write_state_d <= WR_RESP;
        WR_RESP:  if (s_axi.bready) write_state_d <= WR_IDLE;
        default:  write_state_d <= WR_IDLE;
      endcase
    end
  end
  /**/

  /// AXI write control logic
  /*!
  * This block manages the internal control and handshake signals for the AXI write channels:
  * - Write address (AW)
  * - Write data (W)
  * - Write response (B)
  *
  * Behavior:
  * - In `WR_IDLE`, the module latches the incoming address channel signals if `s_axi.awvalid` is high,
  *   and asserts `s_axi.awready` to accept the transaction.
  *
  * - In `WR_BURST`, the module accepts write data when `s_axi.wvalid`
  *   is asserted and raises `s_axi.wready`.
  *   The burst increment logic is commented out here, as burst transfers are not supported
  *   due to PolarFire interconnect compatibility issues.
  *
  * - In WR_RESP:   Sends the write response (`s_axi.bvalid`) and echoes the
  *                 transaction ID. When the master acknowledges by asserting
  *                 `s_axi.bready`, the FSM returns to WR_IDLE.
  *
  * All control signals are reset to default values upon reset.
  */
  always_ff @(posedge axi_clk_i) begin : axi_write_ctrl
    if (!rstn_i) begin
      s_axi_awid_q    <= '0;
      s_axi_awaddr_q  <= '0;
      s_axi_awready_q <= '0;
      s_axi_wready_q  <= '0;
      s_axi_bid_q     <= '0;
      s_axi_bresp_q   <= '0;
      s_axi_bvalid_q  <= '0;
    end
    else begin
      case (write_state_d)
        WR_IDLE: begin
          s_axi_bvalid_q <= 1'b0;

          if (s_axi.awvalid) begin
            s_axi_awid_q    <= s_axi.awid;
            s_axi_awaddr_q  <= s_axi.awaddr;
            s_axi_awready_q <= 1'b1;
          end
        end

        WR_BURST: begin
          s_axi_awready_q <= 1'b0;
          s_axi_wready_q  <= s_axi.wvalid;
        end

        WR_RESP: begin
          s_axi_wready_q <= 1'b0;
          s_axi_bid_q    <= s_axi_awid_q;
          s_axi_bresp_q  <= 2'b00;
          s_axi_bvalid_q <= 1'b1;
        end

        default: ;
      endcase
    end
  end

  /// Output driven by axi_write_ctrl
  assign s_axi.awready = s_axi_awready_q;
  /// Output driven by axi_write_ctrl
  assign s_axi.wready  = s_axi_wready_q;
  /// Output driven by axi_write_ctrl
  assign s_axi.bid     = s_axi_bid_q;
  /// Output driven by axi_write_ctrl
  assign s_axi.bresp   = s_axi_bresp_q;
  /// Output driven by axi_write_ctrl
  assign s_axi.bvalid  = s_axi_bvalid_q;
  /**/

  /// AXI machine read FSM
  /*!
  * This state machine governs the AXI read transaction lifecycle.
  * It manages the transition between idle and active burst states,
  * ensuring proper handshaking.
  *
  * - RD_IDLE: Waits for a valid read address phase (`s_axi.arvalid`).
  *            Once received, transitions to `RD_BURST`.
  *
  * - RD_BURST: Actively sends read data beats to the AXI master.
  *             Transitions back to `RD_IDLE` when
  *             the last beat is sent (`s_axi_rlast_q`).
  *
  * The state is updated on the rising edge of the AXI clock (`axi_clk_i`),
  * and is reset to `RD_IDLE` when `rstn_i` is asserted low.
  */
  always_ff @(posedge axi_clk_i) begin : axi_read_fsm
    if (!rstn_i) read_state_d <= RD_IDLE;
    else begin
      case (read_state_d)
        RD_IDLE:  if (s_axi.arvalid) read_state_d <= RD_BURST;
        RD_BURST: if (s_axi_rlast_q) read_state_d <= RD_IDLE;
        default:  read_state_d <= RD_IDLE;
      endcase
    end
  end
  /**/

  /// AXI read control logic
  /*!
  * This block manages the control path for AXI read transactions.
  * It registers the AXI address channel information and
  * controls the response channel behavior.
  *
  * On reset:
  * - All internal control registers are cleared.
  *
  * In `RD_IDLE` state:
  * - Waits for a valid address phase (`s_axi.arvalid`).
  * - Captures the transaction metadata:
  *     - Transaction ID, address, burst length, burst type, and size.
  * - Asserts `ARREADY` to acknowledge the transaction.
  *
  * In `RD_BURST` state:
  * - Clears `ARREADY` to prevent accepting new addresses.
  * - If `RREADY` is asserted by the master:
  *     - Asserts `RVALID` to return data.
  *     - Updates the address for the next beat in case of burst (`INCR` mode).
  *     - Decrements the burst counter (`ARLEN`) to track progress.
  *     - Sets `RLAST` when the last beat of the burst is reached.
  *
  * AXI response signals (`RID`, `RRESP`, `RLAST`, `RVALID`)
  * are driven combinatorially from the registered control fields
  * to maintain timing consistency.
  */
  always_ff @(posedge axi_clk_i) begin : axi_read_ctrl
    if (!rstn_i) begin
      s_axi_arid_q    <= '0;
      s_axi_araddr_q  <= '0;
      s_axi_arlen_q   <= '0;
      s_axi_arsize_q  <= '0;
      s_axi_arburst_q <= '0;
      s_axi_arready_q <= '0;
      s_axi_rresp_q   <= '0;
      s_axi_rlast_q   <= '0;
      s_axi_rvalid_q  <= '0;
    end
    else begin
      case (read_state_d)
        RD_IDLE: begin
          s_axi_rlast_q  <= 1'b0;
          s_axi_rvalid_q <= 1'b0;

          if (s_axi.arvalid) begin
            s_axi_arid_q    <= s_axi.arid;
            s_axi_araddr_q  <= s_axi.araddr;
            s_axi_arlen_q   <= s_axi.arlen;
            s_axi_arsize_q  <= s_axi.arsize;
            s_axi_arburst_q <= s_axi.arburst;
            s_axi_arready_q <= 1'b1;
          end
        end

        RD_BURST: begin
          s_axi_arready_q <= 1'b0;

          if (s_axi.rready) begin
            s_axi_rvalid_q <= 1'b1;
            s_axi_arlen_q  <= s_axi_arlen_q - 1;
            if (s_axi_arburst_q != 2'b00) s_axi_araddr_q <= s_axi_araddr_q + (1 << s_axi_arsize_q);
            if (s_axi_arlen_q == 0) s_axi_rlast_q <= 1'b1;
          end
          else s_axi_rvalid_q <= 1'b0;
        end

        default: ;
      endcase
    end
  end

  /// Output driven by axi_read_ctrl
  assign s_axi.arready = s_axi_arready_q;
  /// Output driven by axi_read_ctrl
  assign s_axi.rid     = s_axi_arid_q;
  /// Output driven by axi_read_ctrl
  assign s_axi.rresp   = s_axi_rresp_q;
  /// Output driven by axi_read_ctrl
  assign s_axi.rlast   = s_axi_rlast_q;
  /// Output driven by axi_read_ctrl
  assign s_axi.rvalid  = s_axi_rvalid_q;
  /**/

  /// Select RAM address from the active AXI write or read transaction
  assign ram_addr_o  = write_state_d == WR_BURST ? s_axi_awaddr_q :
      read_state_d == RD_BURST ? s_axi_araddr_q : '0;
  /// Forward AXI write data to the RAM write port
  assign ram_wdata_o = s_axi.wdata;
  /// Forward AXI write strobes as RAM byte enables
  assign ram_be_o    = s_axi.wstrb;
  /// Assert RAM write enable when a valid AXI write data beat is transferred
  assign ram_wren_o  = write_state_d == WR_BURST && s_axi.wvalid;
  /// Assert RAM read enable while serving an AXI read transaction
  assign ram_rden_o = read_state_d == RD_BURST && s_axi.rready && !s_axi_rvalid_q;
  /// Return RAM read data on the AXI read data channel
  assign s_axi.rdata = ram_rdata_i;

endmodule
