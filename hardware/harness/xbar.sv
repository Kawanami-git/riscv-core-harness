// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       xbar.sv
\brief      Crossbar used by the riscv-core-harness core to address memories
\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  Crossbar that routes memory-mapped transactions from the RISC-V core (simple valid/enable style) to several target memory blocks.

  Address decoding uses configurable "address tags" extracted from
  bits TagMsb:TagLsb of the address to select the target:
    - Data RAM
    - Shared RAM (platform-to-core path)
    - Shared RAM (core-to-platform path)

\remarks
  - TODO: Improve comments.

\section xbar_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version of the module.            |
********************************************************************************
*/

module xbar #(
    /// Architecture (either 32-bit or 64-bit)
    parameter int unsigned                   Archi               = 32,
    /// Most-significant bit used to extract the address tag (inclusive)
    parameter int unsigned                   TagMsb              = 19,
    /// Least-significant bit used to extract the address tag (inclusive)
    parameter int unsigned                   TagLsb              = 16,
    /// Tag identifying the Data RAM region (TAG_MSB:TAG_LSB)
    parameter logic        [TagMsb-TagLsb:0] DataRamAddrTag,
    /// Tag for platform-to-core shared RAM (AXI write -> core read)
    parameter logic        [TagMsb-TagLsb:0] PtcSharedRamAddrTag,
    /// Tag for core-to-platform shared RAM (core write -> AXI read)
    parameter logic        [TagMsb-TagLsb:0] CtpSharedRamAddrTag
) (
    /* Global signals */
    /// core clock
    input  wire                 core_clk_i,
    /// core reset, active low
    input  wire                 core_rstn_i,
    /* Core signals */
    /// Address transfer request
    input  wire                 core_req_i,
    /// Grant: Ready to accept address transfert
    output wire                 core_gnt_o,
    /// Address for memory access
    input  wire [    Archi-1:0] core_addr_i,
    /// Write enable (1: write - 0: read)
    input  wire                 core_we_i,
    /// Response transfer valid
    output wire                 core_rvalid_o,
    /// Read data
    output wire [Archi - 1 : 0] core_rdata_o,
    /// Error response
    output wire                 core_err_o,
    /* Data RAM signals */
    /// Data RAM port B write enable
    output                      data_ram_b_wren_o,
    /// Data RAM port B read enable
    output                      data_ram_b_rden_o,
    /// Data RAM port B read data
    input  wire [Archi - 1 : 0] data_ram_b_rdata_i,
    /// Data RAM port B grant
    input                       data_ram_b_gnt_i,
    /// Data RAM port B response valid
    input                       data_ram_b_rvalid_i,
    /// Data RAM port B error response
    input                       data_ram_b_err_i,
    /* Platform-to-core shared RAM signals */
    /// Platform-to-core shared RAM port B read enable
    output                      ptc_ram_b_rden_o,
    /// Platform-to-core shared RAM port B write enable
    output                      ptc_ram_b_wren_o,
    /// Platform-to-core shared RAM port B read data
    input  wire [Archi - 1 : 0] ptc_ram_b_rdata_i,
    /// Platform-to-core shared RAM port B grant
    input                       ptc_ram_b_gnt_i,
    /// Platform-to-core shared RAM port B response valid
    input                       ptc_ram_b_rvalid_i,
    /// Platform-to-core shared RAM port B error response
    input                       ptc_ram_b_err_i,
    /* Core-to-platform shared RAM signals */
    /// Core-to-platform shared RAM port A read enable
    output                      ctp_ram_a_rden_o,
    /// Core-to-platform shared RAM port A write enable
    output                      ctp_ram_a_wren_o,
    /// Core-to-platform shared RAM port A read data
    input  wire [Archi - 1 : 0] ctp_ram_a_rdata_i,
    /// Core-to-platform shared RAM port A grant
    input                       ctp_ram_a_gnt_i,
    /// Core-to-platform shared RAM port A response valid
    input                       ctp_ram_a_rvalid_i,
    /// Core-to-platform shared RAM port A error response
    input                       ctp_ram_a_err_i
);

  /******************** DECLARATION ********************/
  /* parameters verification */

  /* local parameters */

  /* machine states */
  /// Core memory request address register
  reg [Archi - 1 : 0] core_addr_q;

  /* functions */
  /* verilator lint_off UNUSEDSIGNAL */
  /*!
  * This function returns '1' if the input address match the provided tag, otherwise '0'.
  * It allows to select a slave according an input address.
  */
  function automatic logic is_matching_tag(input logic [Archi-1:0] addr,
                                           input logic [TagMsb:TagLsb] tag);
    return addr[TagMsb:TagLsb] == tag;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  /* wires */

  /* registers */

  /********************             ********************/

  /*!
  * When a core read request occurs, the data is
  * provided by the memory at the next cycle.
  *
  * However, as the core is pipelined, the core
  * address will also change at the next cycle.
  * This means that the mux used to redirect the
  * memory output (according to the address) may
  * not redirect the memory data to the core.
  *
  * To avoid this behavior, the address is registered
  * and used for the mux to properly provide to the
  * core with the data.
  */
  always_ff @(posedge core_clk_i) begin : core_address
    if (!core_rstn_i) begin
      core_addr_q <= '0;
    end
    else begin
      core_addr_q <= core_addr_i;
    end
  end

  /// Drive data ram write enable
  assign data_ram_b_wren_o = is_matching_tag(
      core_addr_i, DataRamAddrTag
  ) ? core_req_i && core_we_i : {1{1'b0}};
  assign data_ram_b_rden_o = is_matching_tag(
      core_addr_i, DataRamAddrTag
  ) ? core_req_i && !core_we_i : {1{1'b0}};

  /// Drive Platform-to-Core shared ram write enable
  assign ptc_ram_b_wren_o = is_matching_tag(
      core_addr_i, PtcSharedRamAddrTag
  ) ? core_req_i && core_we_i : {1{1'b0}};
  assign ptc_ram_b_rden_o = is_matching_tag(
      core_addr_i, PtcSharedRamAddrTag
  ) ? core_req_i && !core_we_i : {1{1'b0}};

  /// Drive Core-to-Platform shared ram write enable
  assign ctp_ram_a_wren_o = is_matching_tag(
      core_addr_i, CtpSharedRamAddrTag
  ) ? core_req_i && core_we_i : {1{1'b0}};
  assign ctp_ram_a_rden_o = is_matching_tag(
      core_addr_i, CtpSharedRamAddrTag
  ) ? core_req_i && !core_we_i : {1{1'b0}};

  /// Retreive read data
  assign core_rdata_o = is_matching_tag(
      core_addr_q, DataRamAddrTag
  ) ? data_ram_b_rdata_i : is_matching_tag(
      core_addr_q, PtcSharedRamAddrTag
  ) ? ptc_ram_b_rdata_i : is_matching_tag(
      core_addr_q, CtpSharedRamAddrTag
  ) ? ctp_ram_a_rdata_i : {Archi{1'b0}};

  /// Retreive granted flag
  assign core_gnt_o = is_matching_tag(
      core_addr_i, DataRamAddrTag
  ) ? data_ram_b_gnt_i : is_matching_tag(
      core_addr_i, PtcSharedRamAddrTag
  ) ? ptc_ram_b_gnt_i : is_matching_tag(
      core_addr_i, CtpSharedRamAddrTag
  ) ? ctp_ram_a_gnt_i : 1'b0;

  /// Retreive rvalid flag
  assign core_rvalid_o = is_matching_tag(
      core_addr_i, DataRamAddrTag
  ) ? data_ram_b_rvalid_i : is_matching_tag(
      core_addr_i, PtcSharedRamAddrTag
  ) ? ptc_ram_b_rvalid_i : is_matching_tag(
      core_addr_i, CtpSharedRamAddrTag
  ) ? ctp_ram_a_rvalid_i : 'b0;

  /// Retreive error flag
  assign core_err_o = is_matching_tag(
      core_addr_i, DataRamAddrTag
  ) ? data_ram_b_err_i : is_matching_tag(
      core_addr_i, PtcSharedRamAddrTag
  ) ? ptc_ram_b_err_i : is_matching_tag(
      core_addr_i, CtpSharedRamAddrTag
  ) ? ctp_ram_a_err_i : 'b0;

endmodule
