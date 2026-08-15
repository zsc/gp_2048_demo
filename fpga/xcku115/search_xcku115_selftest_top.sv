`timescale 1ns/1ps

`ifdef SIM
module search_xcku115_selftest_top #(
  parameter integer WORKERS = 32,
  parameter integer VECTOR_COUNT = 64
) (
  input  logic         sim_clk,
  input  logic         sim_reset,
  output logic [511:0] sim_status
);
`else
module search_xcku115_selftest_top #(
  parameter integer WORKERS = 32,
  parameter integer VECTOR_COUNT = 64
) (
  input wire sys_clk_p,
  input wire sys_clk_n
);
`endif
  localparam logic [2:0] ST_RESET = 3'd0;
  localparam logic [2:0] ST_START = 3'd1;
  localparam logic [2:0] ST_WAIT  = 3'd2;
  localparam logic [2:0] ST_DONE  = 3'd3;
  localparam integer MAX_MOVE_MISMATCHES = VECTOR_COUNT / 10;

`ifdef SIM
  wire test_clk = sim_clk;
  wire reset = sim_reset;
`else
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
  wire test_clk;
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
    .O(test_clk)
  );

  reg [3:0] reset_release = 4'b0000;
  always @(posedge test_clk or negedge cfg_eos) begin
    if (!cfg_eos)
      reset_release <= 4'b0000;
    else
      reset_release <= {reset_release[2:0], 1'b1};
  end
  wire reset = !reset_release[3];
`endif

  (* rom_style = "block" *) reg [63:0] board_rom [0:VECTOR_COUNT-1];
  (* rom_style = "distributed" *) reg [2:0] move_rom [0:VECTOR_COUNT-1];
  (* rom_style = "block" *) reg [63:0] calls_rom [0:VECTOR_COUNT-1];
  (* rom_style = "block" *) reg [63:0] expanded_rom [0:VECTOR_COUNT-1];
  (* rom_style = "block" *) reg [63:0] cutoffs_rom [0:VECTOR_COUNT-1];
  initial begin
    $readmemh("search_boards.mem", board_rom);
    $readmemh("search_moves.mem", move_rom);
    $readmemh("search_calls.mem", calls_rom);
    $readmemh("search_expanded.mem", expanded_rom);
    $readmemh("search_cutoffs.mem", cutoffs_rom);
  end

  reg [2:0] state = ST_RESET;
  reg [6:0] test_index = 7'd0;
  reg [6:0] completed = 7'd0;
  reg accel_start = 1'b0;
  reg [31:0] wall_cycles = 32'd0;
  reg [63:0] total_search_cycles = 64'd0;
  reg [63:0] maximum_search_cycles = 64'd0;
  reg [7:0] move_mismatches = 8'd0;
  reg [15:0] metric_mismatches = 16'd0;
  reg first_mismatch_seen = 1'b0;
  reg [7:0] first_mismatch_index = 8'hff;
  reg [2:0] first_expected_move = 3'd0;
  reg [2:0] first_actual_move = 3'd0;
  reg overflow_seen = 1'b0;
  reg done = 1'b0;
  reg pass = 1'b0;
  reg timeout = 1'b0;

  wire accel_busy;
  wire accel_done;
  wire [2:0] accel_move;
  wire [63:0] accel_cycles;
  wire [63:0] accel_calls;
  wire [63:0] accel_expanded;
  wire [63:0] accel_cutoffs;
  wire accel_overflow;

  search_accel #(.WORKERS(WORKERS)) u_search (
    .clock(test_clk),
    .reset(reset),
    .start(accel_start),
    .board_i(board_rom[test_index]),
    .budget_i(16'd500),
    .busy(accel_busy),
    .done(accel_done),
    .move_o(accel_move),
    .cycles_o(accel_cycles),
    .calls_o(accel_calls),
    .expanded_o(accel_expanded),
    .cutoffs_o(accel_cutoffs),
    .overflow_o(accel_overflow)
  );

  wire move_matches = accel_move == move_rom[test_index];
  wire metrics_match = accel_calls == calls_rom[test_index] &&
      accel_expanded == expanded_rom[test_index] &&
      accel_cutoffs == cutoffs_rom[test_index];

  always @(posedge test_clk) begin
    accel_start <= 1'b0;
    if (reset) begin
      state <= ST_RESET;
      test_index <= 7'd0;
      completed <= 7'd0;
      wall_cycles <= 32'd0;
      total_search_cycles <= 64'd0;
      maximum_search_cycles <= 64'd0;
      move_mismatches <= 8'd0;
      metric_mismatches <= 16'd0;
      first_mismatch_seen <= 1'b0;
      first_mismatch_index <= 8'hff;
      first_expected_move <= 3'd0;
      first_actual_move <= 3'd0;
      overflow_seen <= 1'b0;
      done <= 1'b0;
      pass <= 1'b0;
      timeout <= 1'b0;
    end else begin
      wall_cycles <= wall_cycles + 32'd1;
      overflow_seen <= overflow_seen | accel_overflow;
      case (state)
        ST_RESET: state <= ST_START;

        ST_START: begin
          accel_start <= 1'b1;
          state <= ST_WAIT;
        end

        ST_WAIT: begin
          if (accel_done) begin
            completed <= completed + 7'd1;
            total_search_cycles <= total_search_cycles + accel_cycles;
            if (accel_cycles > maximum_search_cycles)
              maximum_search_cycles <= accel_cycles;
            if (!move_matches)
              move_mismatches <= move_mismatches + 8'd1;
            if (!metrics_match)
              metric_mismatches <= metric_mismatches + 16'd1;
            if ((!move_matches || !metrics_match || accel_overflow) &&
                !first_mismatch_seen) begin
              first_mismatch_seen <= 1'b1;
              first_mismatch_index <= {1'b0, test_index};
              first_expected_move <= move_rom[test_index];
              first_actual_move <= accel_move;
            end

            if (test_index == VECTOR_COUNT - 1) begin
              done <= 1'b1;
              pass <= (metric_mismatches == 16'd0) && metrics_match &&
                  ((move_mismatches + (move_matches ? 0 : 1)) <=
                   MAX_MOVE_MISMATCHES) &&
                  !overflow_seen && !accel_overflow;
              state <= ST_DONE;
            end else begin
              test_index <= test_index + 7'd1;
              state <= ST_START;
            end
          end
        end

        default: state <= ST_DONE;
      endcase

      if (!done && wall_cycles == 32'd100000000) begin
        done <= 1'b1;
        pass <= 1'b0;
        timeout <= 1'b1;
        state <= ST_DONE;
      end
    end
  end

  reg [511:0] status;
  always @* begin
    status = 512'd0;
    status[31:0] = 32'h3230_4853;
    status[39:32] = 8'd1;
    status[40] = done;
    status[41] = pass;
    status[42] = timeout;
    status[43] = overflow_seen;
    status[46:44] = state;
    status[54:47] = VECTOR_COUNT;
    status[62:55] = {1'b0, completed};
    status[70:63] = move_mismatches;
    status[86:71] = metric_mismatches;
    status[94:87] = first_mismatch_index;
    status[97:95] = first_expected_move;
    status[100:98] = first_actual_move;
    status[108:101] = WORKERS;
    status[116:109] = 8'd8;
    status[148:117] = wall_cycles;
    status[212:149] = total_search_cycles;
    status[276:213] = maximum_search_cycles;
    status[340:277] = accel_cycles;
    status[404:341] = accel_calls;
    status[468:405] = accel_expanded;
    status[511:469] = accel_cutoffs[42:0];
  end

  search_jtag_status #(.WIDTH(512)) u_status (.status_i(status));

`ifdef SIM
  assign sim_status = status;
`else
  wire startup_unused = cfgclk_unused ^ cfgmclk_unused ^ cfg_preq_unused ^
      ^cfg_di_unused ^ accel_busy;
`endif
endmodule
