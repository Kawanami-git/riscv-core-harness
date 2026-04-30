// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       axi_if.sv
\brief      AXI bus interface

\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  This interface groups AXI address, data, and response channels.

  The signal directions are defined through modports:
  - master: AXI manager / initiator side.
  - slave : AXI subordinate / target side.
  - monitor: passive observation side.

\section axi_if_version_history Version history
| Version | Date       | Author     | Description                    |
|:-------:|:----------:|:-----------|:-------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial AXI interface version. |
********************************************************************************
*/

interface axi_if #(
    /// Address width
    parameter int unsigned AddrWidth = 32,
    /// Data width
    parameter int unsigned DataWidth = 32,
    /// AXI byte-enable/strobe width
    parameter int unsigned BeWidth   = DataWidth / 8,
    /// AXI transaction ID width
    parameter int unsigned IdWidth   = 8
);

  // ---------------------------------------------------------------------------
  // Write address channel
  // ---------------------------------------------------------------------------

  /// AWID write address ID
  logic [    IdWidth - 1 : 0] awid;
  /// AWADDR write address
  logic [AddrWidth   - 1 : 0] awaddr;
  /// AWLEN burst length
  logic [              7 : 0] awlen;
  /// AWSIZE burst size
  logic [              2 : 0] awsize;
  /// AWBURST burst type
  logic [              1 : 0] awburst;
  /// AWLOCK lock type
  logic [              1 : 0] awlock;
  /// AWCACHE cache attributes
  logic [              3 : 0] awcache;
  /// AWPROT protection attributes
  logic [              2 : 0] awprot;
  /// AWVALID write address valid
  logic                       awvalid;
  /// AWREADY write address ready
  logic                       awready;

  // ---------------------------------------------------------------------------
  // Write data channel
  // ---------------------------------------------------------------------------

  /// WDATA write data
  logic [DataWidth   - 1 : 0] wdata;
  /// WSTRB write byte strobes
  logic [    BeWidth - 1 : 0] wstrb;
  /// WLAST last write transfer
  logic                       wlast;
  /// WVALID write data valid
  logic                       wvalid;
  /// WREADY write data ready
  logic                       wready;

  // ---------------------------------------------------------------------------
  // Write response channel
  // ---------------------------------------------------------------------------

  /// BID write response ID
  logic [    IdWidth - 1 : 0] bid;
  /// BRESP write response status
  logic [              1 : 0] bresp;
  /// BVALID write response valid
  logic                       bvalid;
  /// BREADY write response ready
  logic                       bready;

  // ---------------------------------------------------------------------------
  // Read address channel
  // ---------------------------------------------------------------------------

  /// ARID read address ID
  logic [    IdWidth - 1 : 0] arid;
  /// ARADDR read address
  logic [AddrWidth   - 1 : 0] araddr;
  /// ARLEN burst length
  logic [              7 : 0] arlen;
  /// ARSIZE burst size
  logic [              2 : 0] arsize;
  /// ARBURST burst type
  logic [              1 : 0] arburst;
  /// ARLOCK lock type
  logic [              1 : 0] arlock;
  /// ARCACHE cache attributes
  logic [              3 : 0] arcache;
  /// ARPROT protection attributes
  logic [              2 : 0] arprot;
  /// ARVALID read address valid
  logic                       arvalid;
  /// ARREADY read address ready
  logic                       arready;

  // ---------------------------------------------------------------------------
  // Read data channel
  // ---------------------------------------------------------------------------

  /// RID read response ID
  logic [    IdWidth - 1 : 0] rid;
  /// RDATA read data.
  logic [DataWidth   - 1 : 0] rdata;
  /// RRESP read response status
  logic [              1 : 0] rresp;
  /// RLAST last read transfer
  logic                       rlast;
  /// RVALID read data valid
  logic                       rvalid;
  /// RREADY read data ready
  logic                       rready;

  // ---------------------------------------------------------------------------
  // Modports
  // ---------------------------------------------------------------------------

  /// AXI slave/subordinate side
  modport slave(
      input awid,
      input awaddr,
      input awlen,
      input awsize,
      input awburst,
      input awlock,
      input awcache,
      input awprot,
      input awvalid,
      output awready,

      input wdata,
      input wstrb,
      input wlast,
      input wvalid,
      output wready,

      output bid,
      output bresp,
      output bvalid,
      input bready,

      input arid,
      input araddr,
      input arlen,
      input arsize,
      input arburst,
      input arlock,
      input arcache,
      input arprot,
      input arvalid,
      output arready,

      output rid,
      output rdata,
      output rresp,
      output rlast,
      output rvalid,
      input rready
  );

  /// AXI master/manager side
  modport master(
      output awid,
      output awaddr,
      output awlen,
      output awsize,
      output awburst,
      output awlock,
      output awcache,
      output awprot,
      output awvalid,
      input awready,

      output wdata,
      output wstrb,
      output wlast,
      output wvalid,
      input wready,

      input bid,
      input bresp,
      input bvalid,
      output bready,

      output arid,
      output araddr,
      output arlen,
      output arsize,
      output arburst,
      output arlock,
      output arcache,
      output arprot,
      output arvalid,
      input arready,

      input rid,
      input rdata,
      input rresp,
      input rlast,
      input rvalid,
      output rready
  );

  /// Passive AXI monitor side
  modport monitor(
      input awid,
      input awaddr,
      input awlen,
      input awsize,
      input awburst,
      input awlock,
      input awcache,
      input awprot,
      input awvalid,
      input awready,

      input wdata,
      input wstrb,
      input wlast,
      input wvalid,
      input wready,

      input bid,
      input bresp,
      input bvalid,
      input bready,

      input arid,
      input araddr,
      input arlen,
      input arsize,
      input arburst,
      input arlock,
      input arcache,
      input arprot,
      input arvalid,
      input arready,

      input rid,
      input rdata,
      input rresp,
      input rlast,
      input rvalid,
      input rready
  );

endinterface
