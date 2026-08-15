`timescale 1ns/1ps

module search_xcku115_queue_top #(
  parameter integer GAME_COUNT = 16384,
  parameter integer ACTIVE_GAME_COUNT = 128,
  parameter integer SEARCH_ENGINES = 4,
  parameter integer WORKERS_PER_ENGINE = 16,
  parameter integer NODE_BUDGET = 1000,
  parameter integer REPLAY_GAMES = 4,
  parameter integer MAX_REPLAY_RECORDS = 4096,
  parameter logic [31:0] BASE_SEED = 32'h2048_c0de
) (
  input wire sys_clk_p,
  input wire sys_clk_n
);
  localparam integer SUMMARY_PAGES = (GAME_COUNT + 3) / 4;
  localparam integer SUMMARY_PAGE_ADDRESS_WIDTH = $clog2(SUMMARY_PAGES);
  localparam integer REPLAY_PAGES = MAX_REPLAY_RECORDS / 4;
  localparam integer REPLAY_PAGE_ADDRESS_WIDTH = $clog2(REPLAY_PAGES);
  localparam integer REPLAY_GAME_ADDRESS_WIDTH = $clog2(REPLAY_GAMES);
  localparam integer JTAG_ADDRESS_WIDTH = 14;
  localparam logic [JTAG_ADDRESS_WIDTH-1:0] SUMMARY_PAGE_BASE = 14'd1;
  localparam logic [JTAG_ADDRESS_WIDTH-1:0] REPLAY_PAGE_BASE =
      SUMMARY_PAGE_BASE + SUMMARY_PAGES;

  wire cfgclk_unused;
  wire cfgmclk_unused;
  wire cfg_eos;
  wire cfg_preq_unused;
  wire [3:0] cfg_di_unused;
  STARTUPE3 u_startup (
    .CFGCLK(cfgclk_unused),
    .CFGMCLK(cfgmclk_unused),
    .DI(cfg_di_unused),
    .EOS(cfg_eos),
    .PREQ(cfg_preq_unused),
    .DO(4'b0000),
    .DTS(4'b1111),
    .FCSBO(1'b0),
    .FCSBTS(1'b1),
    .GSR(1'b0),
    .GTS(1'b0),
    .KEYCLEARB(1'b1),
    .PACK(1'b0),
    .USRCCLKO(1'b0),
    .USRCCLKTS(1'b1),
    .USRDONEO(1'b1),
    .USRDONETS(1'b1)
  );

  wire sys_clk_300mhz;
  wire game_clk;
  IBUFDS #(
    .DIFF_TERM("FALSE"),
    .IBUF_LOW_PWR("FALSE"),
    .IOSTANDARD("DIFF_SSTL12")
  ) u_sys_clk_ibuf (
    .I(sys_clk_p),
    .IB(sys_clk_n),
    .O(sys_clk_300mhz)
  );
  BUFGCE_DIV #(.BUFGCE_DIVIDE(5)) u_extclk_div5 (
    .I(sys_clk_300mhz),
    .CE(1'b1),
    .CLR(1'b0),
    .O(game_clk)
  );

  reg [3:0] reset_release = 4'b0000;
  always @(posedge game_clk or negedge cfg_eos) begin
    if (!cfg_eos)
      reset_release <= 4'b0000;
    else
      reset_release <= {reset_release[2:0], 1'b1};
  end
  wire reset = !reset_release[3];

  logic [SUMMARY_PAGE_ADDRESS_WIDTH-1:0] summary_page_address;
  logic [511:0] summary_page_data;
  logic [REPLAY_GAME_ADDRESS_WIDTH-1:0] replay_game_address;
  logic [REPLAY_PAGE_ADDRESS_WIDTH-1:0] replay_page_address;
  logic [511:0] replay_page_data;
  logic tournament_busy;
  logic tournament_done;
  logic [$clog2(GAME_COUNT+1)-1:0] completed_count;
  logic [$clog2(GAME_COUNT+1)-1:0] win_count;
  logic [63:0] total_moves;
  logic [63:0] total_search_cycles;
  logic [63:0] wall_cycles;
  logic [SEARCH_ENGINES-1:0] engine_busy;
  logic [3:0] tournament_state;

  game2048_tournament_queue #(
    .GAME_COUNT(GAME_COUNT),
    .ACTIVE_GAME_COUNT(ACTIVE_GAME_COUNT),
    .SEARCH_ENGINES(SEARCH_ENGINES),
    .WORKERS_PER_ENGINE(WORKERS_PER_ENGINE),
    .NODE_BUDGET(NODE_BUDGET),
    .REPLAY_GAMES(REPLAY_GAMES),
    .MAX_REPLAY_RECORDS(MAX_REPLAY_RECORDS),
    .BASE_SEED(BASE_SEED),
    .SUMMARY_PAGE_ADDRESS_WIDTH(SUMMARY_PAGE_ADDRESS_WIDTH),
    .REPLAY_GAME_ADDRESS_WIDTH(REPLAY_GAME_ADDRESS_WIDTH),
    .REPLAY_PAGE_ADDRESS_WIDTH(REPLAY_PAGE_ADDRESS_WIDTH)
  ) u_tournament (
    .clock(game_clk),
    .reset(reset),
    .summary_page_address_i(summary_page_address),
    .summary_page_data_o(summary_page_data),
    .replay_game_address_i(replay_game_address),
    .replay_page_address_i(replay_page_address),
    .replay_page_data_o(replay_page_data),
    .busy_o(tournament_busy),
    .done_o(tournament_done),
    .completed_count_o(completed_count),
    .win_count_o(win_count),
    .total_moves_o(total_moves),
    .total_search_cycles_o(total_search_cycles),
    .wall_cycles_o(wall_cycles),
    .engine_busy_o(engine_busy),
    .state_o(tournament_state)
  );

  logic [JTAG_ADDRESS_WIDTH-1:0] requested_page;
  logic [JTAG_ADDRESS_WIDTH-1:0] replay_page_offset;
  logic [511:0] header_page;
  logic [511:0] selected_page;

  always_comb begin
    summary_page_address = requested_page - SUMMARY_PAGE_BASE;
    replay_page_offset = requested_page - REPLAY_PAGE_BASE;
    replay_page_address = replay_page_offset[REPLAY_PAGE_ADDRESS_WIDTH-1:0];
    replay_game_address = replay_page_offset[
        REPLAY_PAGE_ADDRESS_WIDTH + REPLAY_GAME_ADDRESS_WIDTH - 1:
        REPLAY_PAGE_ADDRESS_WIDTH];

    header_page = 512'd0;
    header_page[31:0] = 32'h5132_3048;
    header_page[39:32] = 8'd2;
    header_page[40] = tournament_done;
    header_page[41] = tournament_busy;
    header_page[57:42] = 16'(GAME_COUNT);
    header_page[65:58] = 8'(SEARCH_ENGINES);
    header_page[73:66] = 8'(WORKERS_PER_ENGINE);
    header_page[81:74] = 8'd8;
    header_page[97:82] = 16'(NODE_BUDGET);
    header_page[105:98] = 8'(REPLAY_GAMES);
    header_page[121:106] = 16'(MAX_REPLAY_RECORDS);
    header_page[153:122] = BASE_SEED;
    header_page[167:154] = SUMMARY_PAGE_BASE;
    header_page[183:168] = 16'(SUMMARY_PAGES);
    header_page[197:184] = REPLAY_PAGE_BASE;
    header_page[213:198] = 16'(REPLAY_PAGES);
    header_page[229:214] = 16'(completed_count);
    header_page[245:230] = 16'(win_count);
    header_page[309:246] = total_moves;
    header_page[373:310] = total_search_cycles;
    header_page[437:374] = wall_cycles;
    header_page[445:438] = 8'(engine_busy);
    header_page[449:446] = tournament_state;
    header_page[465:450] = 16'd60;
    header_page[481:466] = 16'(ACTIVE_GAME_COUNT);

    selected_page = 512'd0;
    if (requested_page == '0)
      selected_page = header_page;
    else if ((requested_page >= SUMMARY_PAGE_BASE) &&
             (requested_page < SUMMARY_PAGE_BASE + SUMMARY_PAGES))
      selected_page = summary_page_data;
    else if ((requested_page >= REPLAY_PAGE_BASE) &&
             (requested_page < REPLAY_PAGE_BASE +
              REPLAY_GAMES * REPLAY_PAGES))
      selected_page = replay_page_data;
  end

  search_jtag_pages #(
    .WIDTH(512),
    .ADDRESS_WIDTH(JTAG_ADDRESS_WIDTH)
  ) u_pages (
    .game_clock(game_clk),
    .advance_i(tournament_done),
    .page_data_i(selected_page),
    .page_address_o(requested_page)
  );

  wire startup_unused = cfgclk_unused ^ cfgmclk_unused ^ cfg_preq_unused ^
      ^cfg_di_unused;
endmodule
