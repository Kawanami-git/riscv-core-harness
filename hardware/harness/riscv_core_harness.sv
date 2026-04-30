// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       riscv_core_harness.sv
\brief      riscv-core-harness top-module

\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  Top-level integration environment for RISC-V cores.

  This module connects the core to:
  - Instruction memory
  - Data memory
  - Platform-to-Core asynchronous FIFO (PTC)
  - Core-to-Platform asynchronous FIFO (CTP)
  - System reset peripheral
  - AXI4-Full slave interfaces (subset used)
  - Address-tag-based core interconnect

  AXI scope (subset):
  - Designed for simple, single-beat accesses.
  - Several AXI fields (IDs/PROT/CACHE/LOCK) are wired for interface
    completeness but are not functionally used by the educational flow.
  - Sufficient for loading instruction/data memories, writing the PTC FIFO,
    reading the CTP FIFO, and controlling system reset.
  - Will be improved in the future.

  Memory and communication map (conceptual):
  - INSTR RAM : core fetch read-only, AXI write/read access for firmware loading
  - DATA  RAM : core read/write, AXI write/read access for data loading
  - PTC FIFO  : platform-to-core communication path
  - CTP FIFO  : core-to-platform communication path
  - SYS RESET : AXI-controlled reset peripheral

  The PTC and CTP paths are implemented with asynchronous FIFOs to safely cross
  between the AXI clock domain and the core clock domain.

  In simulation (`SIM`), internal state such as GPRs, CSR/debug signals, memory
  contents, FIFO storage, and pipeline activity are exposed for DPI/Verilator
  testbenches.

\section riscv_core_harness_version_history Version history
| Version | Date       | Author   | Description                                      |
|:-------:|:----------:|:---------|:-------------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami | Initial version of the integration environment.  |
********************************************************************************
*/

module riscv_core_harness

  import target_pkg::TARGET_RTL;
  import target_pkg::TARGET_MPFS_DISCOVERY_KIT;
  import target_pkg::TARGET_CORA_Z7_07S;

#(
    /// Implementation target
    parameter int unsigned             Target          = TARGET_RTL,
    /// Architecture to build (either 32-bit or 64-bit)
    parameter int unsigned             Archi           = 32,
    /// Number of bits in a byte
    parameter int unsigned             ByteLength      = 8,
    /// Number of bits of bytes enable
    parameter int unsigned             BeWidth         = Archi / ByteLength,
    /// Instructions width
    parameter int unsigned             InstrWidth      = 32,
    /// Number of bits of bytes enable for instructions
    parameter int unsigned             InstrBeWidth    = InstrWidth / ByteLength,
    /// Use non-perfect memories
    parameter bit                      NoPerfectMemory = 0,
    /// Core reset vector (byte address)
    parameter logic        [Archi-1:0] StartAddr       = 'h00100000
) (
`ifdef SIM
    /// Simulation CSR overwrite enable
    input  wire                                   csr_en,
    /// Simulation CSR overwrite data
    input  wire  [        Archi          - 1 : 0] csr_data,
    /// Full GPR file view (read-only mirror)
    output wire  [        Archi          - 1 : 0] gpr_memory           [              NB_GPR],
    /// CSR read address from decode
    output wire  [                          11:0] decode_csr_raddr,
    /// System reset RAM contents (exposed to TB)
    output wire  [                 Archi - 1 : 0] sys_reset_mem        [     SYS_RESET_DEPTH],
    /// Instruction RAM contents (exposed to TB)
    output logic [            InstrWidth - 1 : 0] instr_dpram_mem      [     INSTR_RAM_DEPTH],
    /// Data RAM contents (exposed to TB)
    output logic [         Archi         - 1 : 0] data_dpram_mem       [      DATA_RAM_DEPTH],
    /// PTC RAM contents (exposed to TB)
    output logic [         Archi         - 1 : 0] ptc_dpram_mem        [PTC_SHARED_RAM_DEPTH],
    /// CTP RAM contents (exposed to TB)
    output logic [         Archi         - 1 : 0] ctp_dpram_mem        [CTP_SHARED_RAM_DEPTH],
    /// Pipeline flush flag
    output wire                                   pipeline_flush,
    /// Writeback to GPR write enable
    output wire                                   instr_committed,
`endif
    /* Global signals*/
    /// Core clock
    input  wire                                   core_clk_i,
    /// AXI clock
    input  wire                                   axi_clk_i,
    /// AXI active-low reset
    input  wire                                   axi_rstn_i,
    /* Sys reset AXI signals */
    /// AWID (sys reset)
    input  wire  [                         7 : 0] s_sys_reset_awid_i,
    /// AWADDR (sys reset)
    input  wire  [        Archi          - 1 : 0] s_sys_reset_awaddr_i,
    /// AWLEN (sys reset)
    input  wire  [                         7 : 0] s_sys_reset_awlen_i,
    /// AWSIZE (sys reset)
    input  wire  [                         2 : 0] s_sys_reset_awsize_i,
    /// AWBURST (sys reset)
    input  wire  [                         1 : 0] s_sys_reset_awburst_i,
    /// AWLOCK (unused, sys reset)
    input  wire  [                         1 : 0] s_sys_reset_awlock_i,
    /// AWCACHE (unused, sys reset)
    input  wire  [                         3 : 0] s_sys_reset_awcache_i,
    /// AWPROT (unused, sys reset)
    input  wire  [                         2 : 0] s_sys_reset_awprot_i,
    /// AWVALID (sys reset)
    input  wire                                   s_sys_reset_awvalid_i,
    /// AWREADY (sys reset)
    output wire                                   s_sys_reset_awready_o,
    /// WDATA (sys reset)
    input  wire  [     Archi             - 1 : 0] s_sys_reset_wdata_i,
    /// WSTRB (sys reset)
    input  wire  [  BeWidth              - 1 : 0] s_sys_reset_wstrb_i,
    /// WLAST (sys reset)
    input  wire                                   s_sys_reset_wlast_i,
    /// WVALID (sys reset)
    input  wire                                   s_sys_reset_wvalid_i,
    /// WREADY (sys reset)
    output wire                                   s_sys_reset_wready_o,
    /// BID (sys reset)
    output wire  [                           7:0] s_sys_reset_bid_o,
    /// BRESP (sys reset)
    output wire  [                         1 : 0] s_sys_reset_bresp_o,
    /// BVALID (sys reset)
    output wire                                   s_sys_reset_bvalid_o,
    /// BREADY (sys reset)
    input  wire                                   s_sys_reset_bready_i,
    /// ARID (sys reset)
    input  wire  [                         7 : 0] s_sys_reset_arid_i,
    /// ARADDR (sys reset)
    input  wire  [        Archi          - 1 : 0] s_sys_reset_araddr_i,
    /// ARLEN (sys reset)
    input  wire  [                         7 : 0] s_sys_reset_arlen_i,
    /// ARSIZE (sys reset)
    input  wire  [                         2 : 0] s_sys_reset_arsize_i,
    /// ARBURST (sys reset)
    input  wire  [                         1 : 0] s_sys_reset_arburst_i,
    /// ARLOCK (sys reset - unused)
    input  wire  [                         1 : 0] s_sys_reset_arlock_i,
    /// ARCACHE (sys reset - unused)
    input  wire  [                         3 : 0] s_sys_reset_arcache_i,
    /// ARPROT (sys reset - unused)
    input  wire  [                         2 : 0] s_sys_reset_arprot_i,
    /// ARVALID (sys reset)
    input  wire                                   s_sys_reset_arvalid_i,
    /// ARREADY (sys reset)
    output wire                                   s_sys_reset_arready_o,
    /// RID (sys reset)
    output wire  [                         7 : 0] s_sys_reset_rid_o,
    /// RDATA (sys reset)
    output wire  [        Archi          - 1 : 0] s_sys_reset_rdata_o,
    /// RRESP (sys reset)
    output wire  [                         1 : 0] s_sys_reset_rresp_o,
    /// RLAST (sys reset)
    output wire                                   s_sys_reset_rlast_o,
    /// RVALID (sys reset)
    output wire                                   s_sys_reset_rvalid_o,
    /// RREADY (sys reset)
    input  wire                                   s_sys_reset_rready_i,
    /* Instructions AXI signals */
    /// AWID (INSTR)
    input  wire  [                         7 : 0] s_instr_awid_i,
    /// AWADDR (INSTR)
    input  wire  [        Archi          - 1 : 0] s_instr_awaddr_i,
    /// AWLEN (INSTR)
    input  wire  [                         7 : 0] s_instr_awlen_i,
    /// AWSIZE (INSTR)
    input  wire  [                         2 : 0] s_instr_awsize_i,
    /// AWBURST (INSTR)
    input  wire  [                         1 : 0] s_instr_awburst_i,
    /// AWLOCK (unused, INSTR)
    input  wire  [                         1 : 0] s_instr_awlock_i,
    /// AWCACHE (unused, INSTR)
    input  wire  [                         3 : 0] s_instr_awcache_i,
    /// AWPROT (unused, INSTR)
    input  wire  [                         2 : 0] s_instr_awprot_i,
    /// AWVALID (INSTR)
    input  wire                                   s_instr_awvalid_i,
    /// AWREADY (INSTR)
    output wire                                   s_instr_awready_o,
    /// WDATA (INSTR) — fixed 32b words even if Archi=64
    input  wire  [InstrWidth             - 1 : 0] s_instr_wdata_i,
    /// WSTRB (INSTR)
    input  wire  [          InstrBeWidth - 1 : 0] s_instr_wstrb_i,
    /// WLAST (INSTR)
    input  wire                                   s_instr_wlast_i,
    /// WVALID (INSTR)
    input  wire                                   s_instr_wvalid_i,
    /// WREADY (INSTR)
    output wire                                   s_instr_wready_o,
    /// BID (INSTR)
    output wire  [                         7 : 0] s_instr_bid_o,
    /// BRESP (INSTR)
    output wire  [                         1 : 0] s_instr_bresp_o,
    /// BVALID (INSTR)
    output wire                                   s_instr_bvalid_o,
    /// BREADY (INSTR)
    input  wire                                   s_instr_bready_i,
    /// ARID (INSTR)
    input  wire  [                         7 : 0] s_instr_arid_i,
    /// ARADDR (INSTR)
    input  wire  [        Archi          - 1 : 0] s_instr_araddr_i,
    /// ARLEN (INSTR)
    input  wire  [                         7 : 0] s_instr_arlen_i,
    /// ARSIZE (INSTR)
    input  wire  [                         2 : 0] s_instr_arsize_i,
    /// ARBURST (INSTR)
    input  wire  [                         1 : 0] s_instr_arburst_i,
    /// ARLOCK (INSTR - unused)
    input  wire  [                         1 : 0] s_instr_arlock_i,
    /// ARCACHE (INSTR - unused)
    input  wire  [                         3 : 0] s_instr_arcache_i,
    /// ARPROT (INSTR - unused)
    input  wire  [                         2 : 0] s_instr_arprot_i,
    /// ARVALID (INSTR)
    input  wire                                   s_instr_arvalid_i,
    /// ARREADY (INSTR)
    output wire                                   s_instr_arready_o,
    /// RID (INSTR)
    output wire  [                         7 : 0] s_instr_rid_o,
    /// RDATA (INSTR)
    output wire  [   InstrWidth          - 1 : 0] s_instr_rdata_o,
    /// RRESP (INSTR)
    output wire  [                         1 : 0] s_instr_rresp_o,
    /// RLAST (INSTR)
    output wire                                   s_instr_rlast_o,
    /// RVALID (INSTR)
    output wire                                   s_instr_rvalid_o,
    /// RREADY (INSTR)
    input  wire                                   s_instr_rready_i,
    /* Data AXI signals */
    /// AWID (DATA)
    input  wire  [                         7 : 0] s_data_awid_i,
    /// AWADDR (DATA)
    input  wire  [        Archi          - 1 : 0] s_data_awaddr_i,
    /// AWLEN (DATA)
    input  wire  [                         7 : 0] s_data_awlen_i,
    /// AWSIZE (DATA)
    input  wire  [                         2 : 0] s_data_awsize_i,
    /// AWBURST (DATA)
    input  wire  [                         1 : 0] s_data_awburst_i,
    /// AWLOCK (unused, DATA)
    input  wire  [                         1 : 0] s_data_awlock_i,
    /// AWCACHE (unused, DATA)
    input  wire  [                         3 : 0] s_data_awcache_i,
    /// AWPROT (unused, DATA)
    input  wire  [                         2 : 0] s_data_awprot_i,
    /// AWVALID (DATA)
    input  wire                                   s_data_awvalid_i,
    /// AWREADY (DATA)
    output wire                                   s_data_awready_o,
    /// WDATA (DATA)
    input  wire  [        Archi          - 1 : 0] s_data_wdata_i,
    /// WSTRB (DATA)
    input  wire  [          BeWidth      - 1 : 0] s_data_wstrb_i,
    /// WLAST (DATA)
    input  wire                                   s_data_wlast_i,
    /// WVALID (DATA)
    input  wire                                   s_data_wvalid_i,
    /// WREADY (DATA)
    output wire                                   s_data_wready_o,
    /// BID (DATA)
    output wire  [                         7 : 0] s_data_bid_o,
    /// BRESP (DATA)
    output wire  [                         1 : 0] s_data_bresp_o,
    /// BVALID (DATA)
    output wire                                   s_data_bvalid_o,
    /// BREADY (DATA)
    input  wire                                   s_data_bready_i,
    /// ARID (DATA)
    input  wire  [                         7 : 0] s_data_arid_i,
    /// ARADDR (DATA)
    input  wire  [        Archi          - 1 : 0] s_data_araddr_i,
    /// ARLEN (DATA)
    input  wire  [                         7 : 0] s_data_arlen_i,
    /// ARSIZE (DATA)
    input  wire  [                         2 : 0] s_data_arsize_i,
    /// ARBURST (DATA)
    input  wire  [                         1 : 0] s_data_arburst_i,
    /// ARLOCK (DATA - unused)
    input  wire  [                         1 : 0] s_data_arlock_i,
    /// ARCACHE (DATA - unused)
    input  wire  [                         3 : 0] s_data_arcache_i,
    /// ARPROT (DATA - unused)
    input  wire  [                         2 : 0] s_data_arprot_i,
    /// ARVALID (DATA)
    input  wire                                   s_data_arvalid_i,
    /// ARREADY (DATA)
    output wire                                   s_data_arready_o,
    /// RID (DATA)
    output wire  [                         7 : 0] s_data_rid_o,
    /// RDATA (DATA)
    output wire  [        Archi          - 1 : 0] s_data_rdata_o,
    /// RRESP (DATA)
    output wire  [                         1 : 0] s_data_rresp_o,
    /// RLAST (DATA)
    output wire                                   s_data_rlast_o,
    /// RVALID (DATA)
    output wire                                   s_data_rvalid_o,
    /// RREADY (DATA)
    input  wire                                   s_data_rready_i,
    /* Platform-to-Core AXI signals */
    /// AWID (Platform-to-Core)
    input  wire  [                         7 : 0] s_ptc_awid_i,
    /// AWADDR (Platform-to-Core)
    input  wire  [        Archi          - 1 : 0] s_ptc_awaddr_i,
    /// AWLEN (Platform-to-Core)
    input  wire  [                         7 : 0] s_ptc_awlen_i,
    /// AWSIZE (Platform-to-Core)
    input  wire  [                         2 : 0] s_ptc_awsize_i,
    /// AWBURST (Platform-to-Core)
    input  wire  [                         1 : 0] s_ptc_awburst_i,
    /// AWLOCK (unused, Platform-to-Core)
    input  wire  [                         1 : 0] s_ptc_awlock_i,
    /// AWCACHE (unused, Platform-to-Core)
    input  wire  [                         3 : 0] s_ptc_awcache_i,
    /// AWPROT (unused, Platform-to-Core)
    input  wire  [                         2 : 0] s_ptc_awprot_i,
    /// AWVALID (Platform-to-Core)
    input  wire                                   s_ptc_awvalid_i,
    /// AWREADY (Platform-to-Core)
    output wire                                   s_ptc_awready_o,
    /// WDATA (Platform-to-Core)
    input  wire  [        Archi          - 1 : 0] s_ptc_wdata_i,
    /// WSTRB (Platform-to-Core)
    input  wire  [          BeWidth      - 1 : 0] s_ptc_wstrb_i,
    /// WLAST (Platform-to-Core)
    input  wire                                   s_ptc_wlast_i,
    /// WVALID (Platform-to-Core)
    input  wire                                   s_ptc_wvalid_i,
    /// WREADY (Platform-to-Core)
    output wire                                   s_ptc_wready_o,
    /// BID (Platform-to-Core)
    output wire  [                         7 : 0] s_ptc_bid_o,
    /// BRESP (Platform-to-Core)
    output wire  [                         1 : 0] s_ptc_bresp_o,
    /// BVALID (Platform-to-Core)
    output wire                                   s_ptc_bvalid_o,
    /// BREADY (Platform-to-Core)
    input  wire                                   s_ptc_bready_i,
    /// ARID (Platform-to-Core)
    input  wire  [                         7 : 0] s_ptc_arid_i,
    /// ARADDR (Platform-to-Core)
    input  wire  [        Archi          - 1 : 0] s_ptc_araddr_i,
    /// ARLEN (Platform-to-Core)
    input  wire  [                         7 : 0] s_ptc_arlen_i,
    /// ARSIZE (Platform-to-Core)
    input  wire  [                         2 : 0] s_ptc_arsize_i,
    /// ARBURST (Platform-to-Core)
    input  wire  [                         1 : 0] s_ptc_arburst_i,
    /// ARLOCK (Platform-to-Core - unused)
    input  wire  [                         1 : 0] s_ptc_arlock_i,
    /// ARCACHE (Platform-to-Core - unused)
    input  wire  [                         3 : 0] s_ptc_arcache_i,
    /// ARPROT (Platform-to-Core - unused)
    input  wire  [                         2 : 0] s_ptc_arprot_i,
    /// ARVALID (Platform-to-Core)
    input  wire                                   s_ptc_arvalid_i,
    /// ARREADY (Platform-to-Core)
    output wire                                   s_ptc_arready_o,
    /// RID (Platform-to-Core)
    output wire  [                         7 : 0] s_ptc_rid_o,
    /// RDATA (Platform-to-Core)
    output wire  [        Archi          - 1 : 0] s_ptc_rdata_o,
    /// RRESP (Platform-to-Core)
    output wire  [                         1 : 0] s_ptc_rresp_o,
    /// RLAST (Platform-to-Core)
    output wire                                   s_ptc_rlast_o,
    /// RVALID (Platform-to-Core)
    output wire                                   s_ptc_rvalid_o,
    /// RREADY (Platform-to-Core)
    input  wire                                   s_ptc_rready_i,
    /* Core-to-Platform AXI signals */
    /// AWID (Core-to-Platform)
    input  wire  [                         7 : 0] s_ctp_awid_i,
    /// AWADDR (Core-to-Platform)
    input  wire  [        Archi          - 1 : 0] s_ctp_awaddr_i,
    /// AWLEN (Core-to-Platform)
    input  wire  [                         7 : 0] s_ctp_awlen_i,
    /// AWSIZE (Core-to-Platform)
    input  wire  [                         2 : 0] s_ctp_awsize_i,
    /// AWBURST (Core-to-Platform)
    input  wire  [                         1 : 0] s_ctp_awburst_i,
    /// AWLOCK (unused, Core-to-Platform)
    input  wire  [                         1 : 0] s_ctp_awlock_i,
    /// AWCACHE (unused, Core-to-Platform)
    input  wire  [                         3 : 0] s_ctp_awcache_i,
    /// AWPROT (unused, Core-to-Platform)
    input  wire  [                         2 : 0] s_ctp_awprot_i,
    /// AWVALID (Core-to-Platform)
    input  wire                                   s_ctp_awvalid_i,
    /// AWREADY (Core-to-Platform)
    output wire                                   s_ctp_awready_o,
    /// WDATA (Core-to-Platform)
    input  wire  [        Archi          - 1 : 0] s_ctp_wdata_i,
    /// WSTRB (Core-to-Platform)
    input  wire  [          BeWidth      - 1 : 0] s_ctp_wstrb_i,
    /// WLAST (Core-to-Platform)
    input  wire                                   s_ctp_wlast_i,
    /// WVALID (Core-to-Platform)
    input  wire                                   s_ctp_wvalid_i,
    /// WREADY (Core-to-Platform)
    output wire                                   s_ctp_wready_o,
    /// BID (Core-to-Platform)
    output wire  [                         7 : 0] s_ctp_bid_o,
    /// BRESP (Core-to-Platform)
    output wire  [                         1 : 0] s_ctp_bresp_o,
    /// BVALID (Core-to-Platform)
    output wire                                   s_ctp_bvalid_o,
    /// BREADY (Core-to-Platform)
    input  wire                                   s_ctp_bready_i,
    /// ARID (Core-to-Platform)
    input  wire  [                         7 : 0] s_ctp_arid_i,
    /// ARADDR (Core-to-Platform)
    input  wire  [        Archi          - 1 : 0] s_ctp_araddr_i,
    /// ARLEN (Core-to-Platform)
    input  wire  [                         7 : 0] s_ctp_arlen_i,
    /// ARSIZE (Core-to-Platform)
    input  wire  [                         2 : 0] s_ctp_arsize_i,
    /// ARBURST (Core-to-Platform)
    input  wire  [                         1 : 0] s_ctp_arburst_i,
    /// ARLOCK (Core-to-Platform - unused)
    input  wire  [                         1 : 0] s_ctp_arlock_i,
    /// ARCACHE (Core-to-Platform - unused)
    input  wire  [                         3 : 0] s_ctp_arcache_i,
    /// ARPROT (Core-to-Platform - unused)
    input  wire  [                         2 : 0] s_ctp_arprot_i,
    /// ARVALID (Core-to-Platform)
    input  wire                                   s_ctp_arvalid_i,
    /// ARREADY (Core-to-Platform)
    output wire                                   s_ctp_arready_o,
    /// RID (Core-to-Platform)
    output wire  [                         7 : 0] s_ctp_rid_o,
    /// RDATA (Core-to-Platform)
    output wire  [        Archi          - 1 : 0] s_ctp_rdata_o,
    /// RRESP (Core-to-Platform)
    output wire  [                         1 : 0] s_ctp_rresp_o,
    /// RLAST (Core-to-Platform)
    output wire                                   s_ctp_rlast_o,
    /// RVALID (Core-to-Platform)
    output wire                                   s_ctp_rvalid_o,
    /// RREADY (Core-to-Platform)
    input  wire                                   s_ctp_rready_i
);

  /******************** DECLARATION ********************/
  /* parameters verification */
  /// Ensure XLEN is supported by the build (32 or 64)
  if (Archi != 32 && Archi != 64) begin : gen_DATA_WIDTH_check
    $fatal("FATAL ERROR: Only 32-bit and 64-bit DATA_WIDTHtectures are supported.");
  end

  /* local parameters */
`ifdef SIM
  /// Number of integer registers
  localparam int unsigned NB_GPR = 32;
`endif
  /// Address tag most significant bit position (TagMsb)
  localparam int unsigned TAG_MSB = 19;
  /// Address tag least significant bit position (TagMsb)
  localparam int unsigned TAG_LSB = 16;
  /// Number of bits of offset for adressing the Instructions
  localparam int INSTR_ADDR_OFFSET = $clog2(InstrWidth / ByteLength);
  /// Number of bits of offset for the Data
  localparam int DATA_ADDR_OFFSET = $clog2(Archi / ByteLength);
  /// System Reset ram depth (word)
  localparam int unsigned SYS_RESET_DEPTH = 2;
  /// System Reset address range
  localparam int unsigned SYS_RESET_ADDR_WIDTH = $clog2(SYS_RESET_DEPTH);
  /// Instructions ram depth (word)
  localparam int unsigned INSTR_RAM_DEPTH = 4096;
  /// Number of bits of address for the Instruction DPRAM
  localparam int unsigned INSTR_RAM_ADDR_WIDTH = $clog2(INSTR_RAM_DEPTH);
  /// Data ram depth (word)
  localparam int unsigned DATA_RAM_DEPTH = 4096;
  /// Number of bits of address for the Data DPRAM
  localparam int unsigned DATA_RAM_ADDR_WIDTH = $clog2(DATA_RAM_DEPTH);
  /// Data ram tag
  localparam logic [TAG_MSB-TAG_LSB:0] DATA_RAM_ADDR_TAG = 4'b0100;
  /// Platform-to-core shared ram depth (word)
  localparam int unsigned PTC_SHARED_RAM_DEPTH = 4096;
  /// Number of bits of address for the Platform-to-Core DPRAM
  localparam int unsigned PTC_FIFO_ADDR_WIDTH = $clog2(PTC_SHARED_RAM_DEPTH);
  /// Platform-to-core shared ram tag
  localparam logic [TAG_MSB-TAG_LSB:0] PTC_SHARED_RAM_ADDR_TAG = 4'b0101;
  /// Core-to-platform shared ram depth (word)
  localparam int unsigned CTP_SHARED_RAM_DEPTH = 4096;
  /// Number of bits of address for the Core-to-Platform DPRAM
  localparam int unsigned CTP_FIFO_ADDR_WIDTH = $clog2(CTP_SHARED_RAM_DEPTH);
  /// Core-to-platform shared ram tag
  localparam logic [TAG_MSB-TAG_LSB:0] CTP_SHARED_RAM_ADDR_TAG = 4'b0110;

  /* machine states */

  /* functions */

  /* wires */
  /// RISC-V reset (active low)
  wire                              reset0;
  /// Address transfer request
  wire                              core_imem_req;
  /// Grant: Ready to accept address transfert
  wire                              core_imem_gnt;
  /* verilator lint_off UNUSEDSIGNAL */
  /// Address for memory access
  wire [             Archi - 1 : 0] core_imem_addr;
  /* verilator lint_on UNUSEDSIGNAL */
  /// Response transfer valid
  wire                              core_imem_rvalid;
  /// Read data
  wire [                    31 : 0] core_imem_rdata;
  /// Error response
  wire                              core_imem_err;
  /// Address transfer request
  wire                              core_dmem_req;
  /// Grant: Ready to accept address transfert
  wire                              core_dmem_gnt;
  /// Address for memory access
  wire [             Archi - 1 : 0] core_dmem_addr;
  /// Write enable (1: write - 0: read)
  wire                              core_dmem_we;
  /// Write data
  wire [             Archi - 1 : 0] core_dmem_wdata;
  /// Byte enable
  wire [(Archi/ByteLength) - 1 : 0] core_dmem_be;
  /// Response transfer valid
  wire                              core_dmem_rvalid;
  /// Read data
  wire [             Archi - 1 : 0] core_dmem_rdata;
  /// Error response
  wire                              core_dmem_err;

  /* verilator lint_off UNUSEDSIGNAL */
  /// Sys reset RAM address driven by AXI
  wire [           Archi   - 1 : 0] sys_reset_ram_addr;
  /* verilator lint_on UNUSEDSIGNAL */
  /// Sys reset RAM write data driven by AXI
  wire [           Archi   - 1 : 0] sys_reset_ram_wdata;
  /// Sys reset RAM byte enable driven by AXI
  wire [           BeWidth - 1 : 0] sys_reset_ram_be;
  /// Sys reset RAM write enable driven by AXI
  wire                              sys_reset_ram_wren;
  /// Sys reset RAM read enable driven by AXI
  wire                              sys_reset_ram_rden;
  /// Sys reset RAM read data returned to AXI
  wire [           Archi   - 1 : 0] sys_reset_ram_rdata;

  /* verilator lint_off UNUSEDSIGNAL */
  /// Instr RAM port A address driven by AXI
  wire [           Archi   - 1 : 0] instr_ram_a_addr;
  /* verilator lint_on UNUSEDSIGNAL */
  /// Instr RAM port A write data driven by AXI
  wire [      InstrWidth   - 1 : 0] instr_ram_a_wdata;
  /// Instr RAM port A byte enable driven by AXI
  wire [      InstrBeWidth - 1 : 0] instr_ram_a_be;
  /// Instr RAM port A write enable driven by AXI
  wire                              instr_ram_a_wren;
  /// Instr RAM port A read enable driven by AXI
  wire                              instr_ram_a_rden;
  /// Instr RAM port A read data returned to AXI
  wire [      InstrWidth   - 1 : 0] instr_ram_a_rdata;

  /* verilator lint_off UNUSEDSIGNAL */
  /// Data RAM port A address driven by AXI
  wire [           Archi   - 1 : 0] data_ram_a_addr;
  /* verilator lint_on UNUSEDSIGNAL */
  /// Data RAM port A write data driven by AXI
  wire [           Archi   - 1 : 0] data_ram_a_wdata;
  /// Data RAM port A byte enable driven by AXI
  wire [           BeWidth - 1 : 0] data_ram_a_be;
  /// Data RAM port A write enable driven by AXI
  wire                              data_ram_a_wren;
  /// Data RAM port A read enable driven by AXI
  wire                              data_ram_a_rden;
  /// Data RAM port A read data returned to AXI
  wire [           Archi   - 1 : 0] data_ram_a_rdata;
  ///
  wire                              data_ram_b_wren;
  ///
  wire                              data_ram_b_rden;
  ///
  wire [           Archi   - 1 : 0] data_ram_b_rdata;
  ///
  wire                              data_ram_b_gnt;
  ///
  wire                              data_ram_b_rvalid;
  ///
  wire                              data_ram_b_err;

  /* verilator lint_off UNUSEDSIGNAL */
  /// Platform-to-Core RAM port A address driven by AXI
  wire [           Archi   - 1 : 0] ptc_ram_a_addr;
  /* verilator lint_on UNUSEDSIGNAL */
  /// Platform-to-Core RAM port A write data driven by AXI
  wire [           Archi   - 1 : 0] ptc_ram_a_wdata;
  /// Platform-to-Core RAM port A byte enable driven by AXI
  wire [           BeWidth - 1 : 0] ptc_ram_a_be;
  /// Platform-to-Core RAM port A write enable driven by AXI
  wire                              ptc_ram_a_wren;
  /// Platform-to-Core RAM port A read enable driven by AXI
  wire                              ptc_ram_a_rden;
  /// Platform-to-Core RAM port A read data returned to AXI
  wire [           Archi   - 1 : 0] ptc_ram_a_rdata;
  /// Platform-to-Core RAM port B read enable driven by the core
  wire                              ptc_ram_b_rden;
  /// Platform-to-Core RAM port B read data driven by the core
  wire [           Archi   - 1 : 0] ptc_ram_b_rdata;
  /// Platform-to-Core RAM port B granted driven by the core
  wire                              ptc_ram_b_gnt;
  /// Platform-to-Core RAM port B rvalid driven by the core
  wire                              ptc_ram_b_rvalid;
  /// Platform-to-Core RAM port B err driven by the core
  wire                              ptc_ram_b_err;

  /* verilator lint_off UNUSEDSIGNAL */
  /// Core-to-Platform RAM port A address driven by AXI
  wire [           Archi   - 1 : 0] ctp_ram_b_addr;
  /* verilator lint_on UNUSEDSIGNAL */
  /// Core-to-Platform RAM port A read enable driven by AXI
  wire                              ctp_ram_b_rden;
  /// Core-to-Platform RAM port A read data returned to AXI
  wire [           Archi   - 1 : 0] ctp_ram_b_rdata;
  /// Platform-to-Core RAM port B write enable driven by the core
  wire                              ctp_ram_a_wren;
  /// Platform-to-Core RAM port B read enable driven by the core
  wire                              ctp_ram_a_rden;
  /// Platform-to-Core RAM port B read data driven by the core
  wire [           Archi   - 1 : 0] ctp_ram_a_rdata;
  /// Platform-to-Core RAM port B granted driven by the core
  wire                              ctp_ram_a_gnt;
  /// Platform-to-Core RAM port B rvalid driven by the core
  wire                              ctp_ram_a_rvalid;
  /// Platform-to-Core RAM port B err driven by the core
  wire                              ctp_ram_a_err;

  /// System Reset AXI interface
  axi_if #(
      .AddrWidth(Archi),
      .DataWidth(Archi),
      .BeWidth  (BeWidth),
      .IdWidth  (8)
  ) sys_reset_axi ();

  /// Instruction DPRAM AXI interface
  axi_if #(
      .AddrWidth(Archi),
      .DataWidth(InstrWidth),
      .BeWidth  (InstrBeWidth),
      .IdWidth  (8)
  ) instr_axi ();

  /// Data DPRAM AXI interface
  axi_if #(
      .AddrWidth(Archi),
      .DataWidth(Archi),
      .BeWidth  (BeWidth),
      .IdWidth  (8)
  ) data_axi ();

  /// Platform-to-Core DPRAM AXI interface
  axi_if #(
      .AddrWidth(Archi),
      .DataWidth(Archi),
      .BeWidth  (BeWidth),
      .IdWidth  (8)
  ) ptc_axi ();

  /// Core-to-Platform DPRAM AXI interface
  axi_if #(
      .AddrWidth(Archi),
      .DataWidth(Archi),
      .BeWidth  (BeWidth),
      .IdWidth  (8)
  ) ctp_axi ();

  /* registers */
  /// First stage of the reset0 synchronization with core clock domain
  (* ASYNC_REG = "TRUE" *)logic core_reset0_q;
  /// Second stage of the reset0 synchronization with core clock domain
  (* ASYNC_REG = "TRUE" *)logic core_reset0_q_d;
  /// First stage of the reset0 synchronization with axi clock domain
  (* ASYNC_REG = "TRUE" *)logic axi_reset0_q;
  /// Second stage of the reset0 synchronization with axi clock domain
  (* ASYNC_REG = "TRUE" *)logic axi_reset0_q_d;
  /********************             ********************/

  // -----------------------------------------------------------------------------
  // Sys reset AXI flat ports to AXI interface mapping
  // -----------------------------------------------------------------------------
  /// Map 's_sys_reset_awid_i' to sys_reset AXI interface.
  assign sys_reset_axi.awid    = s_sys_reset_awid_i;
  /// Map 's_sys_reset_awaddr_i' to sys_reset AXI interface.
  assign sys_reset_axi.awaddr  = s_sys_reset_awaddr_i;
  /// Map 's_sys_reset_awlen_i' to sys_reset AXI interface.
  assign sys_reset_axi.awlen   = s_sys_reset_awlen_i;
  /// Map 's_sys_reset_awsize_i' to sys_reset AXI interface.
  assign sys_reset_axi.awsize  = s_sys_reset_awsize_i;
  /// Map 's_sys_reset_awburst_i' to sys_reset AXI interface.
  assign sys_reset_axi.awburst = s_sys_reset_awburst_i;
  /// Map 's_sys_reset_awlock_i' to sys_reset AXI interface.
  assign sys_reset_axi.awlock  = s_sys_reset_awlock_i;
  /// Map 's_sys_reset_awcache_i' to sys_reset AXI interface.
  assign sys_reset_axi.awcache = s_sys_reset_awcache_i;
  /// Map 's_sys_reset_awprot_i' to sys_reset AXI interface.
  assign sys_reset_axi.awprot  = s_sys_reset_awprot_i;
  /// Map 's_sys_reset_awvalid_i' to sys_reset AXI interface.
  assign sys_reset_axi.awvalid = s_sys_reset_awvalid_i;
  /// Map sys_reset AXI interface to 's_sys_reset_awready_o'.
  assign s_sys_reset_awready_o = sys_reset_axi.awready;
  /// Map 's_sys_reset_wdata_i' to sys_reset AXI interface.
  assign sys_reset_axi.wdata   = s_sys_reset_wdata_i;
  /// Map 's_sys_reset_wstrb_i' to sys_reset AXI interface.
  assign sys_reset_axi.wstrb   = s_sys_reset_wstrb_i;
  /// Map 's_sys_reset_wlast_i' to sys_reset AXI interface.
  assign sys_reset_axi.wlast   = s_sys_reset_wlast_i;
  /// Map 's_sys_reset_wvalid_i' to sys_reset AXI interface.
  assign sys_reset_axi.wvalid  = s_sys_reset_wvalid_i;
  /// Map sys_reset AXI interface to 's_sys_reset_wready_o'.
  assign s_sys_reset_wready_o  = sys_reset_axi.wready;
  /// Map sys_reset AXI interface to 's_sys_reset_bid_o'.
  assign s_sys_reset_bid_o     = sys_reset_axi.bid;
  /// Map sys_reset AXI interface to 's_sys_reset_bresp_o'.
  assign s_sys_reset_bresp_o   = sys_reset_axi.bresp;
  /// Map sys_reset AXI interface to 's_sys_reset_bvalid_o'.
  assign s_sys_reset_bvalid_o  = sys_reset_axi.bvalid;
  /// Map 's_sys_reset_bready_i' to sys_reset AXI interface.
  assign sys_reset_axi.bready  = s_sys_reset_bready_i;
  /// Map 's_sys_reset_arid_i' to sys_reset AXI interface.
  assign sys_reset_axi.arid    = s_sys_reset_arid_i;
  /// Map 's_sys_reset_araddr_i' to sys_reset AXI interface.
  assign sys_reset_axi.araddr  = s_sys_reset_araddr_i;
  /// Map 's_sys_reset_arlen_i' to sys_reset AXI interface.
  assign sys_reset_axi.arlen   = s_sys_reset_arlen_i;
  /// Map 's_sys_reset_arsize_i' to sys_reset AXI interface.
  assign sys_reset_axi.arsize  = s_sys_reset_arsize_i;
  /// Map 's_sys_reset_arburst_i' to sys_reset AXI interface.
  assign sys_reset_axi.arburst = s_sys_reset_arburst_i;
  /// Map 's_sys_reset_arlock_i' to sys_reset AXI interface.
  assign sys_reset_axi.arlock  = s_sys_reset_arlock_i;
  /// Map 's_sys_reset_arcache_i' to sys_reset AXI interface.
  assign sys_reset_axi.arcache = s_sys_reset_arcache_i;
  /// Map 's_sys_reset_arprot_i' to sys_reset AXI interface.
  assign sys_reset_axi.arprot  = s_sys_reset_arprot_i;
  /// Map 's_sys_reset_arvalid_i' to sys_reset AXI interface.
  assign sys_reset_axi.arvalid = s_sys_reset_arvalid_i;
  /// Map sys_reset AXI interface to 's_sys_reset_arready_o'.
  assign s_sys_reset_arready_o = sys_reset_axi.arready;
  /// Map sys_reset AXI interface to 's_sys_reset_rid_o'.
  assign s_sys_reset_rid_o     = sys_reset_axi.rid;
  /// Map sys_reset AXI interface to 's_sys_reset_rdata_o'.
  assign s_sys_reset_rdata_o   = sys_reset_axi.rdata;
  /// Map sys_reset AXI interface to 's_sys_reset_rresp_o'.
  assign s_sys_reset_rresp_o   = sys_reset_axi.rresp;
  /// Map sys_reset AXI interface to 's_sys_reset_rlast_o'.
  assign s_sys_reset_rlast_o   = sys_reset_axi.rlast;
  /// Map sys_reset AXI interface to 's_sys_reset_rvalid_o'.
  assign s_sys_reset_rvalid_o  = sys_reset_axi.rvalid;
  /// Map 's_sys_reset_rready_i' to sys_reset AXI interface.
  assign sys_reset_axi.rready  = s_sys_reset_rready_i;

  // -----------------------------------------------------------------------------
  // Instr axi AXI flat ports to AXI interface mapping
  // -----------------------------------------------------------------------------
  /// Map 's_instr_awid_i' to instr AXI interface.
  assign instr_axi.awid        = s_instr_awid_i;
  /// Map 's_instr_awaddr_i' to instr AXI interface.
  assign instr_axi.awaddr      = s_instr_awaddr_i;
  /// Map 's_instr_awlen_i' to instr AXI interface.
  assign instr_axi.awlen       = s_instr_awlen_i;
  /// Map 's_instr_awsize_i' to instr AXI interface.
  assign instr_axi.awsize      = s_instr_awsize_i;
  /// Map 's_instr_awburst_i' to instr AXI interface.
  assign instr_axi.awburst     = s_instr_awburst_i;
  /// Map 's_instr_awlock_i' to instr AXI interface.
  assign instr_axi.awlock      = s_instr_awlock_i;
  /// Map 's_instr_awcache_i' to instr AXI interface.
  assign instr_axi.awcache     = s_instr_awcache_i;
  /// Map 's_instr_awprot_i' to instr AXI interface.
  assign instr_axi.awprot      = s_instr_awprot_i;
  /// Map 's_instr_awvalid_i' to instr AXI interface.
  assign instr_axi.awvalid     = s_instr_awvalid_i;
  /// Map instr AXI interface to 's_instr_awready_o'.
  assign s_instr_awready_o     = instr_axi.awready;
  /// Map 's_instr_wdata_i' to instr AXI interface.
  assign instr_axi.wdata       = s_instr_wdata_i;
  /// Map 's_instr_wstrb_i' to instr AXI interface.
  assign instr_axi.wstrb       = s_instr_wstrb_i;
  /// Map 's_instr_wlast_i' to instr AXI interface.
  assign instr_axi.wlast       = s_instr_wlast_i;
  /// Map 's_instr_wvalid_i' to instr AXI interface.
  assign instr_axi.wvalid      = s_instr_wvalid_i;
  /// Map instr AXI interface to 's_instr_wready_o'.
  assign s_instr_wready_o      = instr_axi.wready;
  /// Map instr AXI interface to 's_instr_bid_o'.
  assign s_instr_bid_o         = instr_axi.bid;
  /// Map instr AXI interface to 's_instr_bresp_o'.
  assign s_instr_bresp_o       = instr_axi.bresp;
  /// Map instr AXI interface to 's_instr_bvalid_o'.
  assign s_instr_bvalid_o      = instr_axi.bvalid;
  /// Map 's_instr_bready_i' to instr AXI interface.
  assign instr_axi.bready      = s_instr_bready_i;
  /// Map 's_instr_arid_i' to instr AXI interface.
  assign instr_axi.arid        = s_instr_arid_i;
  /// Map 's_instr_araddr_i' to instr AXI interface.
  assign instr_axi.araddr      = s_instr_araddr_i;
  /// Map 's_instr_arlen_i' to instr AXI interface.
  assign instr_axi.arlen       = s_instr_arlen_i;
  /// Map 's_instr_arsize_i' to instr AXI interface.
  assign instr_axi.arsize      = s_instr_arsize_i;
  /// Map 's_instr_arburst_i' to instr AXI interface.
  assign instr_axi.arburst     = s_instr_arburst_i;
  /// Map 's_instr_arlock_i' to instr AXI interface.
  assign instr_axi.arlock      = s_instr_arlock_i;
  /// Map 's_instr_arcache_i' to instr AXI interface.
  assign instr_axi.arcache     = s_instr_arcache_i;
  /// Map 's_instr_arprot_i' to instr AXI interface.
  assign instr_axi.arprot      = s_instr_arprot_i;
  /// Map 's_instr_arvalid_i' to instr AXI interface.
  assign instr_axi.arvalid     = s_instr_arvalid_i;
  /// Map instr AXI interface to 's_instr_arready_o'.
  assign s_instr_arready_o     = instr_axi.arready;
  /// Map instr AXI interface to 's_instr_rid_o'.
  assign s_instr_rid_o         = instr_axi.rid;
  /// Map instr AXI interface to 's_instr_rdata_o'.
  assign s_instr_rdata_o       = instr_axi.rdata;
  /// Map instr AXI interface to 's_instr_rresp_o'.
  assign s_instr_rresp_o       = instr_axi.rresp;
  /// Map instr AXI interface to 's_instr_rlast_o'.
  assign s_instr_rlast_o       = instr_axi.rlast;
  /// Map instr AXI interface to 's_instr_rvalid_o'.
  assign s_instr_rvalid_o      = instr_axi.rvalid;
  /// Map 's_instr_rready_i' to instr AXI interface.
  assign instr_axi.rready      = s_instr_rready_i;

  // -----------------------------------------------------------------------------
  // Data axi AXI flat ports to AXI interface mapping
  // -----------------------------------------------------------------------------
  /// Map 's_data_awid_i' to data AXI interface.
  assign data_axi.awid         = s_data_awid_i;
  /// Map 's_data_awaddr_i' to data AXI interface.
  assign data_axi.awaddr       = s_data_awaddr_i;
  /// Map 's_data_awlen_i' to data AXI interface.
  assign data_axi.awlen        = s_data_awlen_i;
  /// Map 's_data_awsize_i' to data AXI interface.
  assign data_axi.awsize       = s_data_awsize_i;
  /// Map 's_data_awburst_i' to data AXI interface.
  assign data_axi.awburst      = s_data_awburst_i;
  /// Map 's_data_awlock_i' to data AXI interface.
  assign data_axi.awlock       = s_data_awlock_i;
  /// Map 's_data_awcache_i' to data AXI interface.
  assign data_axi.awcache      = s_data_awcache_i;
  /// Map 's_data_awprot_i' to data AXI interface.
  assign data_axi.awprot       = s_data_awprot_i;
  /// Map 's_data_awvalid_i' to data AXI interface.
  assign data_axi.awvalid      = s_data_awvalid_i;
  /// Map data AXI interface to 's_data_awready_o'.
  assign s_data_awready_o      = data_axi.awready;
  /// Map 's_data_wdata_i' to data AXI interface.
  assign data_axi.wdata        = s_data_wdata_i;
  /// Map 's_data_wstrb_i' to data AXI interface.
  assign data_axi.wstrb        = s_data_wstrb_i;
  /// Map 's_data_wlast_i' to data AXI interface.
  assign data_axi.wlast        = s_data_wlast_i;
  /// Map 's_data_wvalid_i' to data AXI interface.
  assign data_axi.wvalid       = s_data_wvalid_i;
  /// Map data AXI interface to 's_data_wready_o'.
  assign s_data_wready_o       = data_axi.wready;
  /// Map data AXI interface to 's_data_bid_o'.
  assign s_data_bid_o          = data_axi.bid;
  /// Map data AXI interface to 's_data_bresp_o'.
  assign s_data_bresp_o        = data_axi.bresp;
  /// Map data AXI interface to 's_data_bvalid_o'.
  assign s_data_bvalid_o       = data_axi.bvalid;
  /// Map 's_data_bready_i' to data AXI interface.
  assign data_axi.bready       = s_data_bready_i;
  /// Map 's_data_arid_i' to data AXI interface.
  assign data_axi.arid         = s_data_arid_i;
  /// Map 's_data_araddr_i' to data AXI interface.
  assign data_axi.araddr       = s_data_araddr_i;
  /// Map 's_data_arlen_i' to data AXI interface.
  assign data_axi.arlen        = s_data_arlen_i;
  /// Map 's_data_arsize_i' to data AXI interface.
  assign data_axi.arsize       = s_data_arsize_i;
  /// Map 's_data_arburst_i' to data AXI interface.
  assign data_axi.arburst      = s_data_arburst_i;
  /// Map 's_data_arlock_i' to data AXI interface.
  assign data_axi.arlock       = s_data_arlock_i;
  /// Map 's_data_arcache_i' to data AXI interface.
  assign data_axi.arcache      = s_data_arcache_i;
  /// Map 's_data_arprot_i' to data AXI interface.
  assign data_axi.arprot       = s_data_arprot_i;
  /// Map 's_data_arvalid_i' to data AXI interface.
  assign data_axi.arvalid      = s_data_arvalid_i;
  /// Map data AXI interface to 's_data_arready_o'.
  assign s_data_arready_o      = data_axi.arready;
  /// Map data AXI interface to 's_data_rid_o'.
  assign s_data_rid_o          = data_axi.rid;
  /// Map data AXI interface to 's_data_rdata_o'.
  assign s_data_rdata_o        = data_axi.rdata;
  /// Map data AXI interface to 's_data_rresp_o'.
  assign s_data_rresp_o        = data_axi.rresp;
  /// Map data AXI interface to 's_data_rlast_o'.
  assign s_data_rlast_o        = data_axi.rlast;
  /// Map data AXI interface to 's_data_rvalid_o'.
  assign s_data_rvalid_o       = data_axi.rvalid;
  /// Map 's_data_rready_i' to data AXI interface.
  assign data_axi.rready       = s_data_rready_i;

  // -----------------------------------------------------------------------------
  // Platform-to-Core axi AXI flat ports to AXI interface mapping
  // -----------------------------------------------------------------------------
  /// Map 's_ptc_awid_i' to ptc AXI interface.
  assign ptc_axi.awid          = s_ptc_awid_i;
  /// Map 's_ptc_awaddr_i' to ptc AXI interface.
  assign ptc_axi.awaddr        = s_ptc_awaddr_i;
  /// Map 's_ptc_awlen_i' to ptc AXI interface.
  assign ptc_axi.awlen         = s_ptc_awlen_i;
  /// Map 's_ptc_awsize_i' to ptc AXI interface.
  assign ptc_axi.awsize        = s_ptc_awsize_i;
  /// Map 's_ptc_awburst_i' to ptc AXI interface.
  assign ptc_axi.awburst       = s_ptc_awburst_i;
  /// Map 's_ptc_awlock_i' to ptc AXI interface.
  assign ptc_axi.awlock        = s_ptc_awlock_i;
  /// Map 's_ptc_awcache_i' to ptc AXI interface.
  assign ptc_axi.awcache       = s_ptc_awcache_i;
  /// Map 's_ptc_awprot_i' to ptc AXI interface.
  assign ptc_axi.awprot        = s_ptc_awprot_i;
  /// Map 's_ptc_awvalid_i' to ptc AXI interface.
  assign ptc_axi.awvalid       = s_ptc_awvalid_i;
  /// Map ptc AXI interface to 's_ptc_awready_o'.
  assign s_ptc_awready_o       = ptc_axi.awready;
  /// Map 's_ptc_wdata_i' to ptc AXI interface.
  assign ptc_axi.wdata         = s_ptc_wdata_i;
  /// Map 's_ptc_wstrb_i' to ptc AXI interface.
  assign ptc_axi.wstrb         = s_ptc_wstrb_i;
  /// Map 's_ptc_wlast_i' to ptc AXI interface.
  assign ptc_axi.wlast         = s_ptc_wlast_i;
  /// Map 's_ptc_wvalid_i' to ptc AXI interface.
  assign ptc_axi.wvalid        = s_ptc_wvalid_i;
  /// Map ptc AXI interface to 's_ptc_wready_o'.
  assign s_ptc_wready_o        = ptc_axi.wready;
  /// Map ptc AXI interface to 's_ptc_bid_o'.
  assign s_ptc_bid_o           = ptc_axi.bid;
  /// Map ptc AXI interface to 's_ptc_bresp_o'.
  assign s_ptc_bresp_o         = ptc_axi.bresp;
  /// Map ptc AXI interface to 's_ptc_bvalid_o'.
  assign s_ptc_bvalid_o        = ptc_axi.bvalid;
  /// Map 's_ptc_bready_i' to ptc AXI interface.
  assign ptc_axi.bready        = s_ptc_bready_i;
  /// Map 's_ptc_arid_i' to ptc AXI interface.
  assign ptc_axi.arid          = s_ptc_arid_i;
  /// Map 's_ptc_araddr_i' to ptc AXI interface.
  assign ptc_axi.araddr        = s_ptc_araddr_i;
  /// Map 's_ptc_arlen_i' to ptc AXI interface.
  assign ptc_axi.arlen         = s_ptc_arlen_i;
  /// Map 's_ptc_arsize_i' to ptc AXI interface.
  assign ptc_axi.arsize        = s_ptc_arsize_i;
  /// Map 's_ptc_arburst_i' to ptc AXI interface.
  assign ptc_axi.arburst       = s_ptc_arburst_i;
  /// Map 's_ptc_arlock_i' to ptc AXI interface.
  assign ptc_axi.arlock        = s_ptc_arlock_i;
  /// Map 's_ptc_arcache_i' to ptc AXI interface.
  assign ptc_axi.arcache       = s_ptc_arcache_i;
  /// Map 's_ptc_arprot_i' to ptc AXI interface.
  assign ptc_axi.arprot        = s_ptc_arprot_i;
  /// Map 's_ptc_arvalid_i' to ptc AXI interface.
  assign ptc_axi.arvalid       = s_ptc_arvalid_i;
  /// Map ptc AXI interface to 's_ptc_arready_o'.
  assign s_ptc_arready_o       = ptc_axi.arready;
  /// Map ptc AXI interface to 's_ptc_rid_o'.
  assign s_ptc_rid_o           = ptc_axi.rid;
  /// Map ptc AXI interface to 's_ptc_rdata_o'.
  assign s_ptc_rdata_o         = ptc_axi.rdata;
  /// Map ptc AXI interface to 's_ptc_rresp_o'.
  assign s_ptc_rresp_o         = ptc_axi.rresp;
  /// Map ptc AXI interface to 's_ptc_rlast_o'.
  assign s_ptc_rlast_o         = ptc_axi.rlast;
  /// Map ptc AXI interface to 's_ptc_rvalid_o'.
  assign s_ptc_rvalid_o        = ptc_axi.rvalid;
  /// Map 's_ptc_rready_i' to ptc AXI interface.
  assign ptc_axi.rready        = s_ptc_rready_i;

  // -----------------------------------------------------------------------------
  // Core-to-Platform axi AXI flat ports to AXI interface mapping
  // -----------------------------------------------------------------------------
  /// Map 's_ctp_awid_i' to ctp AXI interface.
  assign ctp_axi.awid          = s_ctp_awid_i;
  /// Map 's_ctp_awaddr_i' to ctp AXI interface.
  assign ctp_axi.awaddr        = s_ctp_awaddr_i;
  /// Map 's_ctp_awlen_i' to ctp AXI interface.
  assign ctp_axi.awlen         = s_ctp_awlen_i;
  /// Map 's_ctp_awsize_i' to ctp AXI interface.
  assign ctp_axi.awsize        = s_ctp_awsize_i;
  /// Map 's_ctp_awburst_i' to ctp AXI interface.
  assign ctp_axi.awburst       = s_ctp_awburst_i;
  /// Map 's_ctp_awlock_i' to ctp AXI interface.
  assign ctp_axi.awlock        = s_ctp_awlock_i;
  /// Map 's_ctp_awcache_i' to ctp AXI interface.
  assign ctp_axi.awcache       = s_ctp_awcache_i;
  /// Map 's_ctp_awprot_i' to ctp AXI interface.
  assign ctp_axi.awprot        = s_ctp_awprot_i;
  /// Map 's_ctp_awvalid_i' to ctp AXI interface.
  assign ctp_axi.awvalid       = s_ctp_awvalid_i;
  /// Map ctp AXI interface to 's_ctp_awready_o'.
  assign s_ctp_awready_o       = ctp_axi.awready;
  /// Map 's_ctp_wdata_i' to ctp AXI interface.
  assign ctp_axi.wdata         = s_ctp_wdata_i;
  /// Map 's_ctp_wstrb_i' to ctp AXI interface.
  assign ctp_axi.wstrb         = s_ctp_wstrb_i;
  /// Map 's_ctp_wlast_i' to ctp AXI interface.
  assign ctp_axi.wlast         = s_ctp_wlast_i;
  /// Map 's_ctp_wvalid_i' to ctp AXI interface.
  assign ctp_axi.wvalid        = s_ctp_wvalid_i;
  /// Map ctp AXI interface to 's_ctp_wready_o'.
  assign s_ctp_wready_o        = ctp_axi.wready;
  /// Map ctp AXI interface to 's_ctp_bid_o'.
  assign s_ctp_bid_o           = ctp_axi.bid;
  /// Map ctp AXI interface to 's_ctp_bresp_o'.
  assign s_ctp_bresp_o         = ctp_axi.bresp;
  /// Map ctp AXI interface to 's_ctp_bvalid_o'.
  assign s_ctp_bvalid_o        = ctp_axi.bvalid;
  /// Map 's_ctp_bready_i' to ctp AXI interface.
  assign ctp_axi.bready        = s_ctp_bready_i;
  /// Map 's_ctp_arid_i' to ctp AXI interface.
  assign ctp_axi.arid          = s_ctp_arid_i;
  /// Map 's_ctp_araddr_i' to ctp AXI interface.
  assign ctp_axi.araddr        = s_ctp_araddr_i;
  /// Map 's_ctp_arlen_i' to ctp AXI interface.
  assign ctp_axi.arlen         = s_ctp_arlen_i;
  /// Map 's_ctp_arsize_i' to ctp AXI interface.
  assign ctp_axi.arsize        = s_ctp_arsize_i;
  /// Map 's_ctp_arburst_i' to ctp AXI interface.
  assign ctp_axi.arburst       = s_ctp_arburst_i;
  /// Map 's_ctp_arlock_i' to ctp AXI interface.
  assign ctp_axi.arlock        = s_ctp_arlock_i;
  /// Map 's_ctp_arcache_i' to ctp AXI interface.
  assign ctp_axi.arcache       = s_ctp_arcache_i;
  /// Map 's_ctp_arprot_i' to ctp AXI interface.
  assign ctp_axi.arprot        = s_ctp_arprot_i;
  /// Map 's_ctp_arvalid_i' to ctp AXI interface.
  assign ctp_axi.arvalid       = s_ctp_arvalid_i;
  /// Map ctp AXI interface to 's_ctp_arready_o'.
  assign s_ctp_arready_o       = ctp_axi.arready;
  /// Map ctp AXI interface to 's_ctp_rid_o'.
  assign s_ctp_rid_o           = ctp_axi.rid;
  /// Map ctp AXI interface to 's_ctp_rdata_o'.
  assign s_ctp_rdata_o         = ctp_axi.rdata;
  /// Map ctp AXI interface to 's_ctp_rresp_o'.
  assign s_ctp_rresp_o         = ctp_axi.rresp;
  /// Map ctp AXI interface to 's_ctp_rlast_o'.
  assign s_ctp_rlast_o         = ctp_axi.rlast;
  /// Map ctp AXI interface to 's_ctp_rvalid_o'.
  assign s_ctp_rvalid_o        = ctp_axi.rvalid;
  /// Map 's_ctp_rready_i' to ctp AXI interface.
  assign ctp_axi.rready        = s_ctp_rready_i;

  /*!
   * \brief Synchronize the external reset into the core clock domain.
   *
   * This 2-flop synchronizer reduces the risk of metastability when the
   * external active-low reset `reset0` is sampled by logic running on `core_clk_i`.
   */
  always_ff @(posedge core_clk_i) begin : core_rst_sync
    core_reset0_q   <= reset0;
    core_reset0_q_d <= core_reset0_q;
  end

  /*!
   * \brief Synchronize the external reset into the axi clock domain.
   *
   * This 2-flop synchronizer reduces the risk of metastability when the
   * external active-low reset `reset0` is sampled by logic running on `clk_i`.
   */
  always_ff @(posedge axi_clk_i) begin : axi_rst_sync
    axi_reset0_q   <= reset0;
    axi_reset0_q_d <= axi_reset0_q;
  end

  axi2ram #(
      .AddrWidth(Archi),
      .DataWidth(Archi)
  ) axi2sysreset (
      .axi_clk_i  (axi_clk_i),
      .rstn_i     (axi_rstn_i),
      .s_axi      (sys_reset_axi),
      .ram_addr_o (sys_reset_ram_addr),
      .ram_wdata_o(sys_reset_ram_wdata),
      .ram_be_o   (sys_reset_ram_be),
      .ram_wren_o (sys_reset_ram_wren),
      .ram_rden_o (sys_reset_ram_rden),
      .ram_rdata_i(sys_reset_ram_rdata)
  );

  /// System reset instance
  sys_reset #(
      .DataWidth(Archi),
      .Depth    (SYS_RESET_DEPTH)
  ) sys_reset (
`ifdef SIM
      .mem_o   (sys_reset_mem),
`endif
      .clk_i   (axi_clk_i),
      .rstn_i  (axi_rstn_i),
      .addr_i  (sys_reset_ram_addr[SYS_RESET_ADDR_WIDTH+DATA_ADDR_OFFSET-1:DATA_ADDR_OFFSET]),
      .wdata_i (sys_reset_ram_wdata),
      .be_i    (sys_reset_ram_be),
      .wren_i  (sys_reset_ram_wren),
      .rden_i  (sys_reset_ram_rden),
      .rdata_o (sys_reset_ram_rdata),
      .reset0_o(reset0)
  );



`ifdef SIM
  /* verilator lint_off PINMISSING */
`endif

  /// AXI4 to instruction RAM converter
  axi2ram #(
      .AddrWidth(Archi),
      .DataWidth(InstrWidth)
  ) axi2instr (
      .axi_clk_i  (axi_clk_i),
      .rstn_i     (axi_rstn_i),
      .s_axi      (instr_axi),
      .ram_addr_o (instr_ram_a_addr),
      .ram_wdata_o(instr_ram_a_wdata),
      .ram_be_o   (instr_ram_a_be),
      .ram_wren_o (instr_ram_a_wren),
      .ram_rden_o (instr_ram_a_rden),
      .ram_rdata_i(instr_ram_a_rdata)
  );

  /// Instruction RAM
  dpram #(
      .Target         (Target),
      .NoPerfectMemory(NoPerfectMemory),
      .DataWidth      (InstrWidth),
      .Depth          (INSTR_RAM_DEPTH)
  ) instr_dpram (
`ifdef SIM
      .mem_o     (instr_dpram_mem),
`endif
      .a_clk_i   (axi_clk_i),
      .a_addr_i  (instr_ram_a_addr[INSTR_RAM_ADDR_WIDTH+INSTR_ADDR_OFFSET-1 : INSTR_ADDR_OFFSET]),
      .a_wdata_i (instr_ram_a_wdata),
      .a_be_i    (instr_ram_a_be),
      .a_wren_i  (instr_ram_a_wren),
      .a_rden_i  (instr_ram_a_rden),
      .a_rdata_o (instr_ram_a_rdata),
      /* verilator lint_off PINCONNECTEMPTY */
      .a_gnt_o   (),
      .a_rvalid_o(),
      .a_err_o   (),
      /* verilator lint_on PINCONNECTEMPTY */
      .b_clk_i   (core_clk_i),
      .b_addr_i  (core_imem_addr[INSTR_RAM_ADDR_WIDTH+INSTR_ADDR_OFFSET-1 : INSTR_ADDR_OFFSET]),
      .b_wdata_i ('0),
      .b_be_i    ('0),
      .b_wren_i  ('0),
      .b_rden_i  (core_imem_req),
      .b_rdata_o (core_imem_rdata),
      .b_gnt_o   (core_imem_gnt),
      .b_rvalid_o(core_imem_rvalid),
      .b_err_o   (core_imem_err)
  );

  /// AXI4 to data RAM converter
  axi2ram #(
      .AddrWidth(Archi),
      .DataWidth(Archi)
  ) axi2data (
      .axi_clk_i  (axi_clk_i),
      .rstn_i     (axi_rstn_i),
      .s_axi      (data_axi),
      .ram_addr_o (data_ram_a_addr),
      .ram_wdata_o(data_ram_a_wdata),
      .ram_be_o   (data_ram_a_be),
      .ram_wren_o (data_ram_a_wren),
      .ram_rden_o (data_ram_a_rden),
      .ram_rdata_i(data_ram_a_rdata)
  );

  /// Data RAM
  dpram #(
      .Target         (Target),
      .NoPerfectMemory(NoPerfectMemory),
      .DataWidth      (Archi),
      .Depth          (DATA_RAM_DEPTH)
  ) data_dpram (
`ifdef SIM
      .mem_o     (data_dpram_mem),
`endif
      .a_clk_i   (axi_clk_i),
      .a_addr_i  (data_ram_a_addr[DATA_RAM_ADDR_WIDTH+DATA_ADDR_OFFSET-1 : DATA_ADDR_OFFSET]),
      .a_wdata_i (data_ram_a_wdata),
      .a_be_i    (data_ram_a_be),
      .a_wren_i  (data_ram_a_wren),
      .a_rden_i  (data_ram_a_rden),
      .a_rdata_o (data_ram_a_rdata),
      /* verilator lint_off PINCONNECTEMPTY */
      .a_gnt_o   (),
      .a_rvalid_o(),
      .a_err_o   (),
      /* verilator lint_on PINCONNECTEMPTY */
      .b_clk_i   (core_clk_i),
      .b_addr_i  (core_dmem_addr[DATA_RAM_ADDR_WIDTH+DATA_ADDR_OFFSET-1 : DATA_ADDR_OFFSET]),
      .b_wdata_i (core_dmem_wdata),
      .b_be_i    (core_dmem_be),
      .b_wren_i  (data_ram_b_wren),
      .b_rden_i  (data_ram_b_rden),
      .b_rdata_o (data_ram_b_rdata),
      .b_gnt_o   (data_ram_b_gnt),
      .b_rvalid_o(data_ram_b_rvalid),
      .b_err_o   (data_ram_b_err)
  );

  /// AXI4 to Platform-to-Core RAM converter
  axi2ram #(
      .AddrWidth(Archi),
      .DataWidth(Archi)
  ) axi2ptc (
      .axi_clk_i  (axi_clk_i),
      .rstn_i     (axi_rstn_i),
      .s_axi      (ptc_axi),
      .ram_addr_o (ptc_ram_a_addr),
      .ram_wdata_o(ptc_ram_a_wdata),
      .ram_be_o   (ptc_ram_a_be),
      .ram_wren_o (ptc_ram_a_wren),
      .ram_rden_o (ptc_ram_a_rden),
      .ram_rdata_i(ptc_ram_a_rdata)
  );

  /// AXI4 to platform-to-Core RAM converter
  async_fifo #(
      .Target         (Target),
      .NoPerfectMemory(NoPerfectMemory),
      .DataWidth      (Archi),
      .Depth          (PTC_SHARED_RAM_DEPTH)
  ) ptc_fifo (
`ifdef SIM
      .mem_o     (ptc_dpram_mem),
`endif
      .a_clk_i   (axi_clk_i),
      .a_rstn_i  (axi_reset0_q_d),
      .a_addr_i  (ptc_ram_a_addr[PTC_FIFO_ADDR_WIDTH-1 : 0]),
      .a_wdata_i (ptc_ram_a_wdata),
      .a_be_i    (ptc_ram_a_be),
      .a_wren_i  (ptc_ram_a_wren),
      .a_rden_i  (ptc_ram_a_rden),
      .a_rdata_o (ptc_ram_a_rdata),
      /* verilator lint_off PINCONNECTEMPTY */
      .a_gnt_o   (),
      .a_rvalid_o(),
      .a_err_o   (),
      /* verilator lint_on PINCONNECTEMPTY */
      .b_clk_i   (core_clk_i),
      .b_rstn_i  (core_reset0_q_d),
      .b_addr_i  (core_dmem_addr[PTC_FIFO_ADDR_WIDTH-1 : 0]),
      .b_rden_i  (ptc_ram_b_rden),
      .b_rdata_o (ptc_ram_b_rdata),
      .b_gnt_o   (ptc_ram_b_gnt),
      .b_rvalid_o(ptc_ram_b_rvalid),
      .b_err_o   (ptc_ram_b_err)
  );

  /// AXI4 to Core-to-Platform RAM converter
  axi2ram #(
      .AddrWidth(Archi),
      .DataWidth(Archi)
  ) axi2ctp (
      .axi_clk_i  (axi_clk_i),
      .rstn_i     (axi_rstn_i),
      .s_axi      (ctp_axi),
      .ram_addr_o (ctp_ram_b_addr),
      /* verilator lint_off PINCONNECTEMPTY */
      .ram_wdata_o(),
      .ram_be_o   (),
      .ram_wren_o (),
      /* verilator lint_on PINCONNECTEMPTY */
      .ram_rden_o (ctp_ram_b_rden),
      .ram_rdata_i(ctp_ram_b_rdata)
  );

  /// Core-to-Platform RAM
  async_fifo #(
      .Target         (Target),
      .NoPerfectMemory(NoPerfectMemory),
      .DataWidth      (Archi),
      .Depth          (PTC_SHARED_RAM_DEPTH)
  ) ctp_fifo (
`ifdef SIM
      .mem_o     (ctp_dpram_mem),
`endif
      .a_clk_i   (core_clk_i),
      .a_rstn_i  (core_reset0_q_d),
      .a_addr_i  (core_dmem_addr[CTP_FIFO_ADDR_WIDTH-1 : 0]),
      .a_wdata_i (core_dmem_wdata),
      .a_be_i    (core_dmem_be),
      .a_wren_i  (ctp_ram_a_wren),
      .a_rden_i  (ctp_ram_a_rden),
      .a_rdata_o (ctp_ram_a_rdata),
      .a_gnt_o   (ctp_ram_a_gnt),
      .a_rvalid_o(ctp_ram_a_rvalid),
      .a_err_o   (ctp_ram_a_err),

      .b_clk_i   (axi_clk_i),
      .b_rstn_i  (axi_reset0_q_d),
      .b_addr_i  (ctp_ram_b_addr[CTP_FIFO_ADDR_WIDTH-1 : 0]),
      .b_rden_i  (ctp_ram_b_rden),
      .b_rdata_o (ctp_ram_b_rdata),
      /* verilator lint_off PINCONNECTEMPTY */
      .b_gnt_o   (),
      .b_rvalid_o(),
      .b_err_o   ()
      /* verilator lint_on PINCONNECTEMPTY */
  );

  /// System crossbar
  xbar #(
      .Archi              (Archi),
      .TagMsb             (TAG_MSB),
      .TagLsb             (TAG_LSB),
      .DataRamAddrTag     (DATA_RAM_ADDR_TAG),
      .PtcSharedRamAddrTag(PTC_SHARED_RAM_ADDR_TAG),
      .CtpSharedRamAddrTag(CTP_SHARED_RAM_ADDR_TAG)
  ) xbar (
      .core_clk_i         (core_clk_i),
      .core_rstn_i        (core_reset0_q_d),
      .core_req_i         (core_dmem_req),
      .core_gnt_o         (core_dmem_gnt),
      .core_addr_i        (core_dmem_addr),
      .core_we_i          (core_dmem_we),
      .core_rvalid_o      (core_dmem_rvalid),
      .core_rdata_o       (core_dmem_rdata),
      .core_err_o         (core_dmem_err),
      .data_ram_b_wren_o  (data_ram_b_wren),
      .data_ram_b_rden_o  (data_ram_b_rden),
      .data_ram_b_rdata_i (data_ram_b_rdata),
      .data_ram_b_gnt_i   (data_ram_b_gnt),
      .data_ram_b_rvalid_i(data_ram_b_rvalid),
      .data_ram_b_err_i   (data_ram_b_err),
      .ptc_ram_b_rden_o   (ptc_ram_b_rden),
      .ptc_ram_b_rdata_i  (ptc_ram_b_rdata),
      .ptc_ram_b_gnt_i    (ptc_ram_b_gnt),
      .ptc_ram_b_rvalid_i (ptc_ram_b_rvalid),
      .ptc_ram_b_err_i    (ptc_ram_b_err),
      .ctp_ram_a_rden_o   (ctp_ram_a_rden),
      .ctp_ram_a_wren_o   (ctp_ram_a_wren),
      .ctp_ram_a_rdata_i  (ctp_ram_a_rdata),
      .ctp_ram_a_gnt_i    (ctp_ram_a_gnt),
      .ctp_ram_a_rvalid_i (ctp_ram_a_rvalid),
      .ctp_ram_a_err_i    (ctp_ram_a_err)
  );

  /// RISC-V core instance
  scholar_riscv_core #(
      .Archi       (Archi),
      .StartAddress(StartAddr)
  ) scholar_riscv_core (
`ifdef SIM
      .csr_en_i          (csr_en),
      .csr_data_i        (csr_data),
      .decode_csr_raddr_o(decode_csr_raddr),
      .gpr_memory_o      (gpr_memory),
      .pipeline_flush_o  (pipeline_flush),
      .instr_committed_o (instr_committed),
`endif
      .clk_i             (core_clk_i),
      .rstn_i            (core_reset0_q_d),
      // IF
      .imem_req_o        (core_imem_req),
      .imem_gnt_i        (core_imem_gnt),
      .imem_addr_o       (core_imem_addr),
      .imem_rvalid_i     (core_imem_rvalid),
      .imem_rdata_i      (core_imem_rdata),
      .imem_err_i        (core_imem_err),
      // DF
      .dmem_req_o        (core_dmem_req),
      .dmem_gnt_i        (core_dmem_gnt),
      .dmem_addr_o       (core_dmem_addr),
      .dmem_we_o         (core_dmem_we),
      .dmem_wdata_o      (core_dmem_wdata),
      .dmem_be_o         (core_dmem_be),
      .dmem_rvalid_i     (core_dmem_rvalid),
      .dmem_rdata_i      (core_dmem_rdata),
      .dmem_err_i        (core_dmem_err)
  );

endmodule
