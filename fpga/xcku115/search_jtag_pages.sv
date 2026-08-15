`timescale 1ns/1ps

module search_jtag_pages #(
  parameter integer WIDTH = 512,
  parameter integer ADDRESS_WIDTH = 13
) (
  input  logic                     game_clock,
  input  logic                     advance_i,
  input  logic [WIDTH-1:0]         page_data_i,
  output logic [ADDRESS_WIDTH-1:0] page_address_o
);
`ifdef SIM
  always_comb page_address_o = '0;
  wire unused = game_clock ^ advance_i ^ ^page_data_i;
`else
  wire capture;
  wire drck;
  wire reset;
  wire runtest;
  wire sel;
  wire shift;
  wire tck;
  wire tdi;
  wire tms;
  wire update;

  reg [WIDTH-1:0] shift_data = {WIDTH{1'b0}};
  reg [ADDRESS_WIDTH-1:0] stream_page_tck = {ADDRESS_WIDTH{1'b0}};
  reg [ADDRESS_WIDTH-1:0] requested_page_meta = {ADDRESS_WIDTH{1'b0}};
  reg [ADDRESS_WIDTH-1:0] requested_page_sync = {ADDRESS_WIDTH{1'b0}};
  reg [WIDTH-1:0] capture_data_game = {WIDTH{1'b0}};

  always @(posedge drck) begin
    if (sel && capture)
      shift_data <= capture_data_game;
    else if (sel && shift)
      shift_data <= {tdi, shift_data[WIDTH-1:1]};
  end

  // Before the tournament is complete every scan remains on header page 0,
  // so the host can poll it safely.  Afterwards an all-zero TDI scan still
  // holds the page, while any non-zero TDI scan advances the read-only stream.
  // Only zero/non-zero matters, so the protocol is independent of the tool's
  // bit ordering for the 512-bit shift value.
  always @(posedge update or posedge reset) begin
    if (reset)
      stream_page_tck <= '0;
    else if (advance_i && (|shift_data))
      stream_page_tck <= stream_page_tck + 1'b1;
  end

  // The page number crosses into the 60 MHz game domain.  Page data is then
  // allowed several game clocks to settle before the next slow JTAG scan.
  always @(posedge game_clock) begin
    requested_page_meta <= stream_page_tck;
    requested_page_sync <= requested_page_meta;
    page_address_o <= requested_page_sync;
    capture_data_game <= page_data_i;
  end

  BSCANE2 #(.JTAG_CHAIN(1)) u_bscan (
    .CAPTURE(capture),
    .DRCK(drck),
    .RESET(reset),
    .RUNTEST(runtest),
    .SEL(sel),
    .SHIFT(shift),
    .TCK(tck),
    .TDI(tdi),
    .TDO(shift_data[0]),
    .TMS(tms),
    .UPDATE(update)
  );

  wire unused = reset ^ runtest ^ tck ^ tms;
`endif
endmodule
