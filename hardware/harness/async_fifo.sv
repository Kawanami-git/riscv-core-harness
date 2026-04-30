// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       async_fifo.sv
\brief      Dual-clock asynchronous FIFO using DPRAM storage

\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  This module implements a simple dual-clock asynchronous FIFO using a DPRAM as
  storage.

  Port A is the write-side clock domain.
  Port B is the read-side clock domain.

  Register map per port:
  - Address 0: Local status register
  - Address 4: FIFO data register

  Status register layout:
  - bit  0     : empty flag
  - bit  1     : full flag
  - bits  7:2  : reserved
  - bits 19:8  : rcount[11:0], readable word count
  - bits 31:20 : wcount[11:0], writable word count
  - bits DataWidth-1:32 : reserved, tied to zero

  Write and read event counters are synchronized between clock domains using
  Gray coding. Each side builds a local status word from its local event counter
  and the synchronized remote event counter.

  The FIFO intentionally keeps one storage entry unused. Therefore, the
  effective FIFO capacity is Depth - 1. This avoids empty/full ambiguity while
  keeping the event counters AddrWidth bits wide.

\warning
  Both resets must be asserted together to fully clear the FIFO contents and
  pointer state. Independent single-domain reset while the other domain is
  running is not supported by this simple implementation.

\remarks
  - Port A supports data writes and status reads.
  - Port B supports data reads and status reads.
  - Unsupported accesses return an error response.
  - This module is designed for clarity over feature completeness.

\section async_fifo_version_history Version history
| Version | Date       | Author   | Description                    |
|:-------:|:----------:|:---------|:-------------------------------|
| 1.0     | 28/04/2026 | Kawanami | Initial version of the module. |
********************************************************************************
*/

module async_fifo

  import target_pkg::TARGET_RTL;
  import target_pkg::TARGET_MPFS_DISCOVERY_KIT;
  import target_pkg::TARGET_CORA_Z7_07S;

#(
    /// Implementation target.
    parameter int unsigned Target          = TARGET_RTL,
    /// Enable non-perfect memory behavior when supported by the selected target.
    parameter bit          NoPerfectMemory = 0,
    /// Number of bits in one byte.
    parameter int unsigned ByteLength      = 8,
    /// FIFO data bus width, in bits.
    parameter int unsigned DataWidth       = 32,
    /// FIFO byte-enable width.
    parameter int unsigned BeWidth         = DataWidth / ByteLength,
    /// Number of DataWidth words physically available in FIFO storage.
    parameter int unsigned Depth           = 1280,
    /// FIFO address width.
    parameter int unsigned AddrWidth       = $clog2(Depth)
) (
`ifdef SIM
    /// Simulation-only FIFO storage exposure.
    output logic [DataWidth-1:0] mem_o[Depth],
`endif

    // -------------------------------------------------------------------------
    // Port A: write domain
    // -------------------------------------------------------------------------

    /// Port A clock.
    input logic a_clk_i,
    /// Port A active-low reset.
    input logic a_rstn_i,

    /// Port A register address: 0 = status, 4 = FIFO data.
    input  logic [AddrWidth   - 1 : 0] a_addr_i,
    /// Port A write data.
    input  logic [DataWidth   - 1 : 0] a_wdata_i,
    /// Port A byte enable.
    input  logic [DataWidth/8 - 1 : 0] a_be_i,
    /// Port A write enable; pushes data when address is FIFO data.
    input  logic                       a_wren_i,
    /// Port A read enable; reads local status when address is FIFO status.
    input  logic                       a_rden_i,
    /// Port A read data.
    output logic [DataWidth   - 1 : 0] a_rdata_o,
    /// Port A grant.
    output logic                       a_gnt_o,
    /// Port A response valid.
    output logic                       a_rvalid_o,
    /// Port A error response.
    output logic                       a_err_o,

    // -------------------------------------------------------------------------
    // Port B: read domain
    // -------------------------------------------------------------------------

    /// Port B clock.
    input logic b_clk_i,
    /// Port B active-low reset.
    input logic b_rstn_i,

    /// Port B register address: 0 = status, 4 = FIFO data.
    input  logic [AddrWidth   - 1 : 0] b_addr_i,
    /// Port B write data, unused by this FIFO wrapper.
    input  logic [DataWidth   - 1 : 0] b_wdata_i,
    /// Port B byte enable, unused by this FIFO wrapper.
    input  logic [DataWidth/8 - 1 : 0] b_be_i,
    /// Port B write enable, unsupported by this FIFO wrapper.
    input  logic                       b_wren_i,
    /// Port B read enable; pops data or reads local status.
    input  logic                       b_rden_i,
    /// Port B read data.
    output logic [DataWidth   - 1 : 0] b_rdata_o,
    /// Port B grant.
    output logic                       b_gnt_o,
    /// Port B response valid.
    output logic                       b_rvalid_o,
    /// Port B error response.
    output logic                       b_err_o
);

  // ---------------------------------------------------------------------------
  // Local parameters
  // ---------------------------------------------------------------------------

  /// Width, in bits, of the readable/writable count fields in the status word.
  localparam int unsigned STATUS_COUNT_WIDTH = 12;

  /// Maximum value representable by the status count fields.
  localparam int unsigned STATUS_COUNT_MAX = (1 << STATUS_COUNT_WIDTH) - 1;

  /// Address of the local FIFO status register.
  localparam logic [AddrWidth-1:0] FIFO_STATUS_ADDR = '0;

  /// Address of the FIFO data register.
  localparam logic [AddrWidth-1:0] FIFO_DATA_ADDR = AddrWidth'(BeWidth);

  /// Effective FIFO capacity.
  ///
  /// One storage entry is intentionally kept unused to avoid empty/full
  /// ambiguity with AddrWidth-wide modulo event counters.
  localparam logic [AddrWidth-1:0] FIFO_CAPACITY_COUNT = AddrWidth'(Depth - 1);

  /// Constant increment value used by read and write event counters.
  localparam logic [AddrWidth-1:0] COUNT_ONE = AddrWidth'(1);

  // ---------------------------------------------------------------------------
  // Elaboration checks
  // ---------------------------------------------------------------------------

  /*!
   * \brief Validate FIFO parameters at elaboration time.
   *
   * These checks catch unsupported configurations early during simulation.
   * They are excluded from synthesis.
   */
  // synthesis translate_off
  initial begin
    if (Depth < 2) begin
      $fatal(1, "async_fifo: Depth must be >= 2");
    end

    if (AddrWidth < $clog2(Depth)) begin
      $fatal(1, "async_fifo: AddrWidth is too small for Depth");
    end

    if (AddrWidth < 3) begin
      $fatal(1, "async_fifo: AddrWidth must represent FIFO data address 4");
    end

    if ((Depth - 1) > STATUS_COUNT_MAX) begin
      $fatal(1, "async_fifo: Depth - 1 must fit in the 12-bit status counters");
    end

    if (DataWidth < 32) begin
      $fatal(1, "async_fifo: DataWidth must be >= 32 because status is 32-bit");
    end

    if (FIFO_DATA_ADDR == FIFO_STATUS_ADDR) begin
      $fatal(1, "async_fifo: FIFO data and status addresses overlap");
    end
  end
  // synthesis translate_on

  // ---------------------------------------------------------------------------
  // Utility functions
  // ---------------------------------------------------------------------------

  /*!
   * \brief Convert a binary counter value to Gray code.
   *
   * \param bin_i Binary counter value.
   *
   * \return Equivalent Gray-coded counter value.
   */
  function automatic logic [AddrWidth-1:0] bin_to_gray(input logic [AddrWidth-1:0] bin_i);
    bin_to_gray = (bin_i >> 1) ^ bin_i;
  endfunction

  /*!
   * \brief Convert a Gray-coded counter value to binary.
   *
   * \param gray_i Gray-coded counter value.
   *
   * \return Equivalent binary counter value.
   */
  function automatic logic [AddrWidth-1:0] gray_to_bin(input logic [AddrWidth-1:0] gray_i);
    /// Local binary conversion result.
    logic [AddrWidth-1:0] bin;

    bin[AddrWidth-1] = gray_i[AddrWidth-1];

    for (int i = AddrWidth - 2; i >= 0; i--) begin
      bin[i] = bin[i+1] ^ gray_i[i];
    end

    gray_to_bin = bin;
  endfunction

  /*!
   * \brief Increment a FIFO storage address with wrap-around.
   *
   * \param addr_i Current FIFO storage address.
   *
   * \return Next FIFO storage address.
   */
  function automatic logic [AddrWidth-1:0] incr_addr(input logic [AddrWidth-1:0] addr_i);
    if (addr_i == AddrWidth'(Depth - 1)) begin
      incr_addr = '0;
    end
    else begin
      incr_addr = addr_i + AddrWidth'(1);
    end
  endfunction

  /*!
   * \brief Convert an internal count to the 12-bit status field format.
   *
   * \param count_i Internal FIFO count.
   *
   * \return Count value truncated to 12 bits.
   */
  function automatic logic [11:0] count_to_status(input logic [AddrWidth-1:0] count_i);
    count_to_status = 12'(count_i);
  endfunction

  /*!
   * \brief Build a packed FIFO status word.
   *
   * \param empty_i  FIFO empty flag.
   * \param full_i   FIFO full flag.
   * \param rcount_i Number of readable FIFO words.
   * \param wcount_i Number of writable FIFO words.
   *
   * \return Packed FIFO status word.
   */
  function automatic logic [DataWidth-1:0] build_status_word(
      input logic empty_i, input logic full_i, input logic [AddrWidth-1:0] rcount_i,
      input logic [AddrWidth-1:0] wcount_i);
    /// Temporary packed status word.
    logic [DataWidth-1:0] status;

    status            = '0;

    status[0]         = empty_i;
    status[1]         = full_i;
    status[19:8]      = count_to_status(rcount_i);
    status[31:20]     = count_to_status(wcount_i);

    build_status_word = status;
  endfunction

  // ---------------------------------------------------------------------------
  // FIFO counters and addresses
  // ---------------------------------------------------------------------------

  /// Current write address in the FIFO storage RAM.
  logic [AddrWidth-1:0] waddr_q;

  /// Current read address in the FIFO storage RAM.
  logic [AddrWidth-1:0] raddr_q;

  /// Binary write event counter in the write clock domain.
  logic [AddrWidth-1:0] wcount_bin_q;

  /// Gray-coded write event counter exported toward the read clock domain.
  logic [AddrWidth-1:0] wcount_gray_q;

  /// Binary read event counter in the read clock domain.
  logic [AddrWidth-1:0] rcount_bin_q;

  /// Gray-coded read event counter exported toward the write clock domain.
  logic [AddrWidth-1:0] rcount_gray_q;

  /// Next binary write event counter value.
  logic [AddrWidth-1:0] wcount_bin_next;

  /// Next binary read event counter value.
  logic [AddrWidth-1:0] rcount_bin_next;

  /// Compute the next write event counter value.
  assign wcount_bin_next = wcount_bin_q + COUNT_ONE;

  /// Compute the next read event counter value.
  assign rcount_bin_next = rcount_bin_q + COUNT_ONE;

  // ---------------------------------------------------------------------------
  // CDC synchronizers
  // ---------------------------------------------------------------------------

  /// First synchronization stage for the read counter Gray code in Port A domain.
  (* ASYNC_REG = "TRUE" *)logic [AddrWidth-1:0] rcount_gray_a_meta_q;

  /// Second synchronization stage for the read counter Gray code in Port A domain.
  (* ASYNC_REG = "TRUE" *)logic [AddrWidth-1:0] rcount_gray_a_sync_q;

  /// First synchronization stage for the write counter Gray code in Port B domain.
  (* ASYNC_REG = "TRUE" *)logic [AddrWidth-1:0] wcount_gray_b_meta_q;

  /// Second synchronization stage for the write counter Gray code in Port B domain.
  (* ASYNC_REG = "TRUE" *)logic [AddrWidth-1:0] wcount_gray_b_sync_q;

  /// Read event counter synchronized into Port A domain and converted to binary.
  logic [AddrWidth-1:0] rcount_bin_a_sync;

  /// Write event counter synchronized into Port B domain and converted to binary.
  logic [AddrWidth-1:0] wcount_bin_b_sync;

  /// Convert synchronized read counter from Gray code to binary in Port A domain.
  assign rcount_bin_a_sync = gray_to_bin(rcount_gray_a_sync_q);

  /// Convert synchronized write counter from Gray code to binary in Port B domain.
  assign wcount_bin_b_sync = gray_to_bin(wcount_gray_b_sync_q);

  /*!
   * \brief Synchronize the read event counter into the write clock domain.
   */
  always_ff @(posedge a_clk_i) begin
    if (!a_rstn_i) begin
      rcount_gray_a_meta_q <= '0;
      rcount_gray_a_sync_q <= '0;
    end
    else begin
      rcount_gray_a_meta_q <= rcount_gray_q;
      rcount_gray_a_sync_q <= rcount_gray_a_meta_q;
    end
  end

  /*!
   * \brief Synchronize the write event counter into the read clock domain.
   */
  always_ff @(posedge b_clk_i) begin
    if (!b_rstn_i) begin
      wcount_gray_b_meta_q <= '0;
      wcount_gray_b_sync_q <= '0;
    end
    else begin
      wcount_gray_b_meta_q <= wcount_gray_q;
      wcount_gray_b_sync_q <= wcount_gray_b_meta_q;
    end
  end

  // ---------------------------------------------------------------------------
  // Local FIFO levels and flags
  // ---------------------------------------------------------------------------

  /// FIFO occupancy estimate in the write clock domain.
  logic [AddrWidth-1:0] a_level;

  /// FIFO occupancy estimate in the read clock domain.
  logic [AddrWidth-1:0] b_level;

  /// FIFO full flag in the write clock domain.
  logic                 a_full;

  /// FIFO empty flag in the read clock domain.
  logic                 b_empty;

  /// Compute FIFO occupancy as seen from Port A.
  assign a_level = wcount_bin_q - rcount_bin_a_sync;

  /// Compute FIFO occupancy as seen from Port B.
  assign b_level = wcount_bin_b_sync - rcount_bin_q;

  /// FIFO is full when the write-domain occupancy reaches effective capacity.
  assign a_full  = (a_level >= FIFO_CAPACITY_COUNT);

  /// FIFO is empty when the read-domain occupancy is zero.
  assign b_empty = (b_level == '0);

  // ---------------------------------------------------------------------------
  // Access decoding
  // ---------------------------------------------------------------------------

  /// Port A address selects the FIFO data register.
  logic a_is_data_addr;

  /// Port A address selects the FIFO status register.
  logic a_is_status_addr;

  /// Port A has an active request.
  logic a_has_req;

  /// Port A request is a valid FIFO push.
  logic a_push_req;

  /// Port A request is a valid status read.
  logic a_status_req;

  /// Port A request is invalid or unsupported.
  logic a_invalid_req;

  /// Port B address selects the FIFO data register.
  logic b_is_data_addr;

  /// Port B address selects the FIFO status register.
  logic b_is_status_addr;

  /// Port B has an active request.
  logic b_has_req;

  /// Port B request is a valid FIFO pop.
  logic b_pop_req;

  /// Port B request is a valid status read.
  logic b_status_req;

  /// Port B request is invalid or unsupported.
  logic b_invalid_req;

  /// Decode Port A data register address.
  assign a_is_data_addr   = (a_addr_i == FIFO_DATA_ADDR);

  /// Decode Port A status register address.
  assign a_is_status_addr = (a_addr_i == FIFO_STATUS_ADDR);

  /// Detect any active Port A access.
  assign a_has_req        = a_wren_i || a_rden_i;

  /// Decode a valid Port A push request.
  assign a_push_req       = a_wren_i && !a_rden_i && a_is_data_addr;

  /// Decode a valid Port A status read request.
  assign a_status_req     = a_rden_i && !a_wren_i && a_is_status_addr;

  /// Decode invalid or unsupported Port A accesses.
  assign a_invalid_req    = a_has_req && !(a_push_req || a_status_req);

  /// Decode Port B data register address.
  assign b_is_data_addr   = (b_addr_i == FIFO_DATA_ADDR);

  /// Decode Port B status register address.
  assign b_is_status_addr = (b_addr_i == FIFO_STATUS_ADDR);

  /// Detect any active Port B access.
  assign b_has_req        = b_wren_i || b_rden_i;

  /// Decode a valid Port B pop request.
  assign b_pop_req        = b_rden_i && !b_wren_i && b_is_data_addr;

  /// Decode a valid Port B status read request.
  assign b_status_req     = b_rden_i && !b_wren_i && b_is_status_addr;

  /// Decode invalid or unsupported Port B accesses.
  assign b_invalid_req    = b_has_req && !(b_pop_req || b_status_req);

  // ---------------------------------------------------------------------------
  // DPRAM interface
  // ---------------------------------------------------------------------------

  /// FIFO storage Port A read data.
  logic [DataWidth-1:0] mem_a_rdata;

  /// FIFO storage Port A grant.
  logic                 mem_a_gnt;

  /// FIFO storage Port A response valid.
  logic                 mem_a_rvalid;

  /// FIFO storage Port A error response.
  logic                 mem_a_err;

  /// FIFO storage Port B read data.
  logic [DataWidth-1:0] mem_b_rdata;

  /// FIFO storage Port B grant.
  logic                 mem_b_gnt;

  /// FIFO storage Port B response valid.
  logic                 mem_b_rvalid;

  /// FIFO storage Port B error response.
  logic                 mem_b_err;

  /// FIFO storage Port A write enable.
  logic                 mem_a_wren;

  /// FIFO storage Port B read enable.
  logic                 mem_b_rden;

  /// Write storage only for valid push requests when the FIFO is not full.
  assign mem_a_wren = a_push_req && !a_full;

  /// Read storage only for valid pop requests when the FIFO is not empty.
  assign mem_b_rden = b_pop_req && !b_empty;

  /// FIFO storage memory.
  dpram #(
      .Target         (Target),
      .NoPerfectMemory(NoPerfectMemory),
      .ByteLength     (ByteLength),
      .DataWidth      (DataWidth),
      .BeWidth        (BeWidth),
      .Depth          (Depth),
      .AddrWidth      (AddrWidth)
  ) u_fifo_mem (
`ifdef SIM
      .mem_o(mem_o),
`endif

      .a_clk_i   (a_clk_i),
      .a_addr_i  (waddr_q),
      .a_wdata_i (a_wdata_i),
      .a_be_i    (a_be_i),
      .a_wren_i  (mem_a_wren),
      .a_rden_i  (1'b0),
      .a_rdata_o (mem_a_rdata),
      .a_gnt_o   (mem_a_gnt),
      .a_rvalid_o(mem_a_rvalid),
      .a_err_o   (mem_a_err),

      .b_clk_i   (b_clk_i),
      .b_addr_i  (raddr_q),
      .b_wdata_i (b_wdata_i),
      .b_be_i    (b_be_i),
      .b_wren_i  (1'b0),
      .b_rden_i  (mem_b_rden),
      .b_rdata_o (mem_b_rdata),
      .b_gnt_o   (mem_b_gnt),
      .b_rvalid_o(mem_b_rvalid),
      .b_err_o   (mem_b_err)
  );

  // ---------------------------------------------------------------------------
  // Grants and accepted transfers
  // ---------------------------------------------------------------------------

  /// Accepted FIFO push transfer in Port A domain.
  logic a_push_fire;

  /// Accepted FIFO pop transfer in Port B domain.
  logic b_pop_fire;

  /// A push fires when the request is valid, the FIFO is not full, and RAM grants it.
  assign a_push_fire = a_push_req && !a_full && mem_a_gnt;

  /// A pop fires when the request is valid, the FIFO is not empty, and RAM grants it.
  assign b_pop_fire  = b_pop_req && !b_empty && mem_b_gnt;

  /*!
   * \brief Generate the Port A grant response.
   *
   * Status and invalid requests are handled locally and are granted immediately.
   * Push requests are granted only when the FIFO has space and the storage RAM
   * accepts the write.
   */
  always_comb begin
    if (a_status_req || a_invalid_req) begin
      a_gnt_o = 1'b1;
    end
    else if (a_push_req) begin
      a_gnt_o = !a_full && mem_a_gnt;
    end
    else begin
      a_gnt_o = !a_full && mem_a_gnt;
    end
  end

  /*!
   * \brief Generate the Port B grant response.
   *
   * Status and invalid requests are handled locally and are granted immediately.
   * Pop requests are granted only when the FIFO contains data and the storage RAM
   * accepts the read.
   */
  always_comb begin
    if (b_status_req || b_invalid_req) begin
      b_gnt_o = 1'b1;
    end
    else if (b_pop_req) begin
      b_gnt_o = !b_empty && mem_b_gnt;
    end
    else begin
      b_gnt_o = !b_empty && mem_b_gnt;
    end
  end

  // ---------------------------------------------------------------------------
  // Write-domain pointer update
  // ---------------------------------------------------------------------------

  /*!
   * \brief Update the write address and write event counter.
   *
   * The write pointer advances only after an accepted FIFO push.
   */
  always_ff @(posedge a_clk_i) begin
    if (!a_rstn_i) begin
      waddr_q       <= '0;
      wcount_bin_q  <= '0;
      wcount_gray_q <= '0;
    end
    else if (a_push_fire) begin
      waddr_q       <= incr_addr(waddr_q);
      wcount_bin_q  <= wcount_bin_next;
      wcount_gray_q <= bin_to_gray(wcount_bin_next);
    end
  end

  // ---------------------------------------------------------------------------
  // Read-domain pointer update
  // ---------------------------------------------------------------------------

  /*!
   * \brief Update the read address and read event counter.
   *
   * The read pointer advances only after an accepted FIFO pop.
   */
  always_ff @(posedge b_clk_i) begin
    if (!b_rstn_i) begin
      raddr_q       <= '0;
      rcount_bin_q  <= '0;
      rcount_gray_q <= '0;
    end
    else if (b_pop_fire) begin
      raddr_q       <= incr_addr(raddr_q);
      rcount_bin_q  <= rcount_bin_next;
      rcount_gray_q <= bin_to_gray(rcount_bin_next);
    end
  end

  // ---------------------------------------------------------------------------
  // Status registers
  // ---------------------------------------------------------------------------

  /// Port A local status register.
  logic [DataWidth-1:0] a_status_q;

  /// Port B local status register.
  logic [DataWidth-1:0] b_status_q;

  /// Write event counter used for Port A status computation.
  logic [AddrWidth-1:0] a_wcount_event_status;

  /// Read event counter used for Port A status computation.
  logic [AddrWidth-1:0] a_rcount_event_status;

  /// Write event counter used for Port B status computation.
  logic [AddrWidth-1:0] b_wcount_event_status;

  /// Read event counter used for Port B status computation.
  logic [AddrWidth-1:0] b_rcount_event_status;

  /// FIFO occupancy used to build Port A status.
  logic [AddrWidth-1:0] a_level_status;

  /// FIFO occupancy used to build Port B status.
  logic [AddrWidth-1:0] b_level_status;

  /// Writable word count exposed in Port A status.
  logic [AddrWidth-1:0] a_write_available_status;

  /// Readable word count exposed in Port A status.
  logic [AddrWidth-1:0] a_read_available_status;

  /// Writable word count exposed in Port B status.
  logic [AddrWidth-1:0] b_write_available_status;

  /// Readable word count exposed in Port B status.
  logic [AddrWidth-1:0] b_read_available_status;

  /// Empty flag exposed in Port A status.
  logic                 a_empty_status;

  /// Full flag exposed in Port A status.
  logic                 a_full_status;

  /// Empty flag exposed in Port B status.
  logic                 b_empty_status;

  /// Full flag exposed in Port B status.
  logic                 b_full_status;

  /// Select the write event counter after a potential accepted push.
  assign a_wcount_event_status    = a_push_fire ? wcount_bin_next : wcount_bin_q;

  /// Use the synchronized read event counter in Port A status.
  assign a_rcount_event_status    = rcount_bin_a_sync;

  /// Use the synchronized write event counter in Port B status.
  assign b_wcount_event_status    = wcount_bin_b_sync;

  /// Select the read event counter after a potential accepted pop.
  assign b_rcount_event_status    = b_pop_fire ? rcount_bin_next : rcount_bin_q;

  /// Compute Port A status occupancy.
  assign a_level_status           = a_wcount_event_status - a_rcount_event_status;

  /// Compute Port B status occupancy.
  assign b_level_status           = b_wcount_event_status - b_rcount_event_status;

  /// Compute Port A empty status flag.
  assign a_empty_status           = (a_level_status == '0);

  /// Compute Port A full status flag.
  assign a_full_status            = (a_level_status >= FIFO_CAPACITY_COUNT);

  /// Compute Port B empty status flag.
  assign b_empty_status           = (b_level_status == '0);

  /// Compute Port B full status flag.
  assign b_full_status            = (b_level_status >= FIFO_CAPACITY_COUNT);

  /// Port A readable word count.
  assign a_read_available_status  = a_level_status;

  /// Port B readable word count.
  assign b_read_available_status  = b_level_status;

  /// Port A writable word count.
  assign a_write_available_status = a_full_status ? '0 : FIFO_CAPACITY_COUNT - a_level_status;

  /// Port B writable word count.
  assign b_write_available_status = b_full_status ? '0 : FIFO_CAPACITY_COUNT - b_level_status;

  /*!
   * \brief Update the Port A status register.
   */
  always_ff @(posedge a_clk_i) begin
    if (!a_rstn_i) begin
      a_status_q <= build_status_word(1'b1, 1'b0, '0, FIFO_CAPACITY_COUNT);
    end
    else begin
      a_status_q <= build_status_word(a_empty_status, a_full_status, a_read_available_status,
                                      a_write_available_status);
    end
  end

  /*!
   * \brief Update the Port B status register.
   */
  always_ff @(posedge b_clk_i) begin
    if (!b_rstn_i) begin
      b_status_q <= build_status_word(1'b1, 1'b0, '0, FIFO_CAPACITY_COUNT);
    end
    else begin
      b_status_q <= build_status_word(b_empty_status, b_full_status, b_read_available_status,
                                      b_write_available_status);
    end
  end

  // ---------------------------------------------------------------------------
  // Local status/error responses
  // ---------------------------------------------------------------------------

  /// Port A local response-valid flag for status and invalid accesses.
  logic                 a_local_rvalid_q;

  /// Port A local error flag.
  logic                 a_local_err_q;

  /// Port A local read data.
  logic [DataWidth-1:0] a_local_rdata_q;

  /// Port B local response-valid flag for status and invalid accesses.
  logic                 b_local_rvalid_q;

  /// Port B local error flag.
  logic                 b_local_err_q;

  /// Port B local read data.
  logic [DataWidth-1:0] b_local_rdata_q;

  /*!
   * \brief Generate local Port A responses.
   *
   * Port A local responses are used for status reads and invalid accesses.
   */
  always_ff @(posedge a_clk_i) begin
    if (!a_rstn_i) begin
      a_local_rvalid_q <= 1'b0;
      a_local_err_q    <= 1'b0;
      a_local_rdata_q  <= '0;
    end
    else begin
      a_local_rvalid_q <= a_status_req || a_invalid_req;
      a_local_err_q    <= a_invalid_req;
      a_local_rdata_q  <= a_status_req ? a_status_q : '0;
    end
  end

  /*!
   * \brief Generate local Port B responses.
   *
   * Port B local responses are used for status reads and invalid accesses.
   */
  always_ff @(posedge b_clk_i) begin
    if (!b_rstn_i) begin
      b_local_rvalid_q <= 1'b0;
      b_local_err_q    <= 1'b0;
      b_local_rdata_q  <= '0;
    end
    else begin
      b_local_rvalid_q <= b_status_req || b_invalid_req;
      b_local_err_q    <= b_invalid_req;
      b_local_rdata_q  <= b_status_req ? b_status_q : '0;
    end
  end

  // ---------------------------------------------------------------------------
  // Output response muxing
  // ---------------------------------------------------------------------------

  /// Port A response valid combines local responses and storage RAM responses.
  assign a_rvalid_o = a_local_rvalid_q || mem_a_rvalid;

  /// Port A error combines local access errors and storage RAM errors.
  assign a_err_o    = (a_local_rvalid_q && a_local_err_q) || (mem_a_rvalid && mem_a_err);

  /// Port A read data selects local response data before storage RAM data.
  assign a_rdata_o  = a_local_rvalid_q ? a_local_rdata_q : mem_a_rdata;

  /// Port B response valid combines local responses and storage RAM responses.
  assign b_rvalid_o = b_local_rvalid_q || mem_b_rvalid;

  /// Port B error combines local access errors and storage RAM errors.
  assign b_err_o    = (b_local_rvalid_q && b_local_err_q) || (mem_b_rvalid && mem_b_err);

  /// Port B read data selects local response data before storage RAM data.
  assign b_rdata_o  = b_local_rvalid_q ? b_local_rdata_q : mem_b_rdata;

endmodule
