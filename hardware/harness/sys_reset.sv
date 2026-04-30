// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       sys_reset.sv
\brief      AXI write-only system reset register

\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  This module exposes a simple AXI write-only register used to drive reset
  outputs inside the FPGA design.

  In its current form, only bit 0 of the internal register is exported through
  `reset0_o`. The internal storage width matches `DataWidth`, which allows this
  module to be extended later to control additional reset outputs if needed.

\remarks
  - TODO: .

\section sys_reset_version_history Version history
| Version | Date       | Author   | Description                    |
|:-------:|:----------:|:---------|:-------------------------------|
| 1.0     | 28/04/2026 | Kawanami | Initial version of the module. |
********************************************************************************
*/

module sys_reset #(
    /// Number of bits in a byte
    parameter int          ByteLength = 8,
    /// Data bus width in bits (applies to core and AXI)
    parameter int unsigned DataWidth  = 32,
    /// Number of bits of bytes enable
    parameter int unsigned BeWidth    = DataWidth / ByteLength,
    /// Number of internal reset register words
    parameter int unsigned Depth      = 2,
    /// Address bus width in bits (applies to core and AXI)
    parameter int unsigned AddrWidth  = $clog2(Depth)
) (
`ifdef SIM
    /// (Simulation only) Exposes the internal register storage to the testbench
    output logic [        DataWidth-1:0] mem_o   [Depth],
`endif
    /// Memory clock
    input  wire                          clk_i,
    /// Memory reset (active-low)
    input  wire                          rstn_i,
    /// Memory address
    input  wire  [AddrWidth     - 1 : 0] addr_i,
    /// Memory write data
    input  wire  [DataWidth     - 1 : 0] wdata_i,
    /// Memory byte enable
    input  wire  [  BeWidth     - 1 : 0] be_i,
    /// Memory write enable
    input  wire                          wren_i,
    /// Memory read enable
    input  wire                          rden_i,
    /// Memory read data
    output wire  [DataWidth     - 1 : 0] rdata_o,
    /// Reset output driven by bit 0 of the internal register
    output wire                          reset0_o
);

  /******************** DECLARATION ********************/
  /* parameters verification */

  /* local parameters */

  /* machine states */

  /* functions */

  /* wires */

  /* registers */
  /// Registered read address for port A (held when `rden_i`=`0`)
  reg   [AddrWidth -1:0] addr_i_q;
  /// memory array
  logic [ DataWidth-1:0] mem      [Depth];
  /********************             ********************/

  /// Memory access logic.
  /*!
  * - Writes: per-byte using `be_i`; active when `wren_i`=`1`.
  * - Reads : capture address when `rden_i`=`1`; output is `mem[addr_i_q]`.
  */
  always_ff @(posedge clk_i) begin : ctrl
    if (!rstn_i) begin
      for (int i = 0; i < Depth; i++) begin
        mem[i] <= '0;
      end
    end
    else begin
      if (wren_i) begin
        for (int i = 0; i < BeWidth; i++) begin
          if (be_i[i]) mem[addr_i][i*ByteLength+:ByteLength] <= wdata_i[i*ByteLength+:ByteLength];
        end
      end
      else if (rden_i) begin
        addr_i_q <= addr_i;
      end
    end
  end

  /// Output driven by ctrl
  assign rdata_o  = mem[addr_i_q];

  /// Output driven by mem
  assign reset0_o = mem[0][0];

`ifdef SIM
  /// Output driven by mem
  assign mem_o = mem;
`endif

endmodule
