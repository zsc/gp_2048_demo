`timescale 1ns/1ps

module search_accel #(
  parameter integer WORKERS = 32,
  parameter integer MAX_TASKS = 128
) (
  input  logic        clock,
  input  logic        reset,
  input  logic        start,
  input  logic [63:0] board_i,
  input  logic [15:0] budget_i,
  output logic        busy,
  output logic        done,
  output logic [2:0]  move_o,
  output logic [63:0] cycles_o,
  output logic [63:0] calls_o,
  output logic [63:0] expanded_o,
  output logic [63:0] cutoffs_o,
  output logic        overflow_o
);
  import game2048_pkg::*;

  localparam logic [3:0] S_IDLE           = 4'd0;
  localparam logic [3:0] S_PREPARE        = 4'd1;
  localparam logic [3:0] S_ROOT_INIT      = 4'd2;
  localparam logic [3:0] S_GENERATE       = 4'd3;
  localparam logic [3:0] S_RUN            = 4'd4;
  localparam logic [3:0] S_FINALIZE       = 4'd5;
  localparam logic [3:0] S_CHOOSE         = 4'd6;
  localparam logic [3:0] S_ROOT_DIV_MUL   = 4'd7;
  localparam logic [3:0] S_ROOT_DIV_STORE = 4'd8;
  localparam logic [3:0] S_ALLOCATE       = 4'd9;

  logic [3:0] state;
  logic [63:0] root_input_board;
  logic [15:0] root_budget;
  logic [15:0] nodes_per_move;
  logic [2:0] valid_count;
  logic [2:0] root_direction;

  logic root_valid [0:3];
  logic [63:0] root_board [0:3];
  logic [4:0] root_empty_count [0:3];
  logic [15:0] root_spawn_budget [0:3];
  logic root_tail_mode [0:3];
  logic signed [35:0] root_sum_two [0:3];
  logic signed [35:0] root_sum_four [0:3];
  logic signed [31:0] root_value [0:3];

  logic root_expected_negative;
  logic [39:0] root_expected_magnitude;
  logic [23:0] root_expected_reciprocal;
  (* use_dsp = "yes" *) logic [63:0] root_expected_product;

  logic [15:0] generation_mask;
  logic generation_phase;
  logic [4:0] generation_cursor;

  logic [63:0] task_board [0:MAX_TASKS-1];
  logic [15:0] task_budget [0:MAX_TASKS-1];
  logic [1:0] task_root [0:MAX_TASKS-1];
  logic [1:0] task_phase [0:MAX_TASKS-1];
  logic [7:0] task_count;
  logic [7:0] dispatch_index;
  logic [5:0] dispatch_worker;
  logic [5:0] collect_worker;
  logic [7:0] completed_count;

  logic worker_start [0:WORKERS-1];
  logic worker_busy [0:WORKERS-1];
  logic worker_done [0:WORKERS-1];
  logic [63:0] worker_board [0:WORKERS-1];
  logic [15:0] worker_budget [0:WORKERS-1];
  logic [1:0] worker_root [0:WORKERS-1];
  logic [1:0] worker_phase [0:WORKERS-1];
  logic signed [31:0] worker_value [0:WORKERS-1];
  logic [31:0] worker_calls [0:WORKERS-1];
  logic [31:0] worker_expanded [0:WORKERS-1];
  logic [31:0] worker_cutoffs [0:WORKERS-1];
  logic worker_overflow [0:WORKERS-1];
  logic worker_pending [0:WORKERS-1];

  logic [63:0] moved_root [0:3];
  logic [15:0] root_mask_now;
  logic [4:0] root_empty_now;
  logic [4:0] next_generation_cell;
  logic [32:0] root_budget_times_three_recip;

  logic all_workers_idle;

  integer comb_direction_index;
  integer worker_index;
  integer scan_cell;

  generate
    genvar worker_gen;
    for (worker_gen = 0; worker_gen < WORKERS; worker_gen = worker_gen + 1) begin : workers
      search_worker u_worker (
        .clock(clock),
        .reset(reset),
        .start(worker_start[worker_gen]),
        .board_i(worker_board[worker_gen]),
        .depth_i(5'd9),
        .budget_i(worker_budget[worker_gen]),
        .busy(worker_busy[worker_gen]),
        .done(worker_done[worker_gen]),
        .value_o(worker_value[worker_gen]),
        .calls_o(worker_calls[worker_gen]),
        .expanded_o(worker_expanded[worker_gen]),
        .cutoffs_o(worker_cutoffs[worker_gen]),
        .overflow_o(worker_overflow[worker_gen])
      );
    end
  endgenerate

  always_comb begin
    for (comb_direction_index = 0; comb_direction_index < 4;
         comb_direction_index = comb_direction_index + 1)
      moved_root[comb_direction_index] =
          move_dir(root_input_board, comb_direction_index[1:0]);

    root_mask_now = empty_mask(root_board[root_direction[1:0]]);
    root_empty_now = count_empty(root_board[root_direction[1:0]]);
    root_budget_times_three_recip = root_budget * 17'd43691;

    next_generation_cell = 5'd31;
    for (scan_cell = 0; scan_cell < 16; scan_cell = scan_cell + 1)
      if ((scan_cell >= generation_cursor) && generation_mask[scan_cell] &&
          (next_generation_cell == 5'd31))
        next_generation_cell = scan_cell[4:0];

    all_workers_idle = 1'b1;
    for (worker_index = 0; worker_index < WORKERS; worker_index = worker_index + 1) begin
      if (worker_busy[worker_index] || worker_start[worker_index] ||
          worker_done[worker_index] || worker_pending[worker_index])
        all_workers_idle = 1'b0;
    end
  end

  always_ff @(posedge clock) begin : accelerator_fsm
    integer valid_total;
    integer launch_worker;
    integer ff_direction_index;
    logic [15:0] remaining_after_root;
    logic [15:0] spawn_budget;
    logic signed [31:0] best_value;
    logic [2:0] best_direction;
    logic best_found;
    logic signed [39:0] expectation_numerator;

    done <= 1'b0;
    for (launch_worker = 0; launch_worker < WORKERS; launch_worker = launch_worker + 1)
      worker_start[launch_worker] <= 1'b0;

    if (reset) begin
      state <= S_IDLE;
      busy <= 1'b0;
      done <= 1'b0;
      move_o <= 3'd7;
      cycles_o <= 64'd0;
      calls_o <= 64'd0;
      expanded_o <= 64'd0;
      cutoffs_o <= 64'd0;
      overflow_o <= 1'b0;
      task_count <= 8'd0;
      dispatch_index <= 8'd0;
      dispatch_worker <= 6'd0;
      collect_worker <= 6'd0;
      completed_count <= 8'd0;
      for (launch_worker = 0; launch_worker < WORKERS;
           launch_worker = launch_worker + 1)
        worker_pending[launch_worker] <= 1'b0;
    end else begin
      if (busy)
        cycles_o <= cycles_o + 64'd1;

      case (state)
        S_IDLE: begin
          if (start) begin
            busy <= 1'b1;
            root_input_board <= board_i;
            root_budget <= budget_i;
            cycles_o <= 64'd0;
            calls_o <= 64'd0;
            expanded_o <= 64'd0;
            cutoffs_o <= 64'd0;
            overflow_o <= 1'b0;
            task_count <= 8'd0;
            dispatch_index <= 8'd0;
            dispatch_worker <= 6'd0;
            collect_worker <= 6'd0;
            completed_count <= 8'd0;
            for (launch_worker = 0; launch_worker < WORKERS;
                 launch_worker = launch_worker + 1)
              worker_pending[launch_worker] <= 1'b0;
            state <= S_PREPARE;
          end
        end

        S_PREPARE: begin
          valid_total = 0;
          for (ff_direction_index = 0; ff_direction_index < 4;
               ff_direction_index = ff_direction_index + 1) begin
            root_board[ff_direction_index] <= moved_root[ff_direction_index];
            root_valid[ff_direction_index] <=
                moved_root[ff_direction_index] != root_input_board;
            if (moved_root[ff_direction_index] != root_input_board)
              valid_total = valid_total + 1;
            root_empty_count[ff_direction_index] <= 5'd0;
            root_spawn_budget[ff_direction_index] <= 16'd0;
            root_tail_mode[ff_direction_index] <= 1'b0;
            root_sum_two[ff_direction_index] <= 36'sd0;
            root_sum_four[ff_direction_index] <= 36'sd0;
            root_value[ff_direction_index] <= 32'sd0;
          end
          valid_count <= valid_total[2:0];
          state <= S_ALLOCATE;
        end

        S_ALLOCATE: begin
          if (valid_count == 3'd0) begin
            move_o <= 3'd7;
            busy <= 1'b0;
            done <= 1'b1;
            state <= S_IDLE;
          end else begin
            case (valid_count)
              3'd1: nodes_per_move <= root_budget;
              3'd2: nodes_per_move <= root_budget >> 1;
              3'd3: nodes_per_move <=
                  root_budget_times_three_recip[32:17];
              default: nodes_per_move <= root_budget >> 2;
            endcase
            root_direction <= 3'd0;
            state <= S_ROOT_INIT;
          end
        end

        S_ROOT_INIT: begin
          if (root_direction >= 3'd4) begin
            dispatch_index <= 8'd0;
            dispatch_worker <= 6'd0;
            collect_worker <= 6'd0;
            completed_count <= 8'd0;
            state <= S_RUN;
          end else if (!root_valid[root_direction[1:0]]) begin
            root_direction <= root_direction + 3'd1;
          end else begin
            calls_o <= calls_o + 64'd1;
            if (nodes_per_move == 16'd0) begin
              cutoffs_o <= cutoffs_o + 64'd1;
              root_value[root_direction[1:0]] <=
                  eval_simple_q8(root_board[root_direction[1:0]]);
              root_direction <= root_direction + 3'd1;
            end else begin
              expanded_o <= expanded_o + 64'd1;
              remaining_after_root = nodes_per_move - 16'd1;
              root_empty_count[root_direction[1:0]] <= root_empty_now;
              if (root_empty_now == 5'd0) begin
                root_tail_mode[root_direction[1:0]] <= 1'b1;
                task_board[task_count[6:0]] <= root_board[root_direction[1:0]];
                task_budget[task_count[6:0]] <= remaining_after_root;
                task_root[task_count[6:0]] <= root_direction[1:0];
                task_phase[task_count[6:0]] <= 2'd2;
                task_count <= task_count + 8'd1;
                root_direction <= root_direction + 3'd1;
              end else begin
                spawn_budget = remaining_after_root /
                    ({11'd0, root_empty_now} << 1);
                if (spawn_budget == 16'd0)
                  spawn_budget = 16'd1;
                root_spawn_budget[root_direction[1:0]] <= spawn_budget;
                generation_mask <= root_mask_now;
                generation_phase <= 1'b0;
                generation_cursor <= 5'd0;
                state <= S_GENERATE;
              end
            end
          end
        end

        S_GENERATE: begin
          if (next_generation_cell == 5'd31) begin
            if (!generation_phase) begin
              generation_phase <= 1'b1;
              generation_cursor <= 5'd0;
            end else begin
              root_direction <= root_direction + 3'd1;
              state <= S_ROOT_INIT;
            end
          end else begin
            task_board[task_count[6:0]] <= set_spawn(
                root_board[root_direction[1:0]], next_generation_cell[3:0],
                generation_phase ? 2'd2 : 2'd1);
            task_budget[task_count[6:0]] <= root_spawn_budget[root_direction[1:0]];
            task_root[task_count[6:0]] <= root_direction[1:0];
            task_phase[task_count[6:0]] <= generation_phase ? 2'd1 : 2'd0;
            task_count <= task_count + 8'd1;
            generation_cursor <= next_generation_cell + 5'd1;
          end
        end

        S_RUN: begin
          for (launch_worker = 0; launch_worker < WORKERS;
               launch_worker = launch_worker + 1) begin
            if (worker_done[launch_worker])
              worker_pending[launch_worker] <= 1'b1;
          end

          // Retire one completed worker per cycle.  Per-worker pending bits
          // preserve simultaneous completions without a 32-way adder chain.
          if (worker_pending[collect_worker]) begin
            worker_pending[collect_worker] <= 1'b0;
            completed_count <= completed_count + 8'd1;
            calls_o <= calls_o + {32'd0, worker_calls[collect_worker]};
            expanded_o <= expanded_o +
                {32'd0, worker_expanded[collect_worker]};
            cutoffs_o <= cutoffs_o + {32'd0, worker_cutoffs[collect_worker]};
            overflow_o <= overflow_o | worker_overflow[collect_worker];
            if (worker_phase[collect_worker] == 2'd0)
              root_sum_two[worker_root[collect_worker]] <=
                  root_sum_two[worker_root[collect_worker]] +
                  {{4{worker_value[collect_worker][31]}},
                   worker_value[collect_worker]};
            else if (worker_phase[collect_worker] == 2'd1)
              root_sum_four[worker_root[collect_worker]] <=
                  root_sum_four[worker_root[collect_worker]] +
                  {{4{worker_value[collect_worker][31]}},
                   worker_value[collect_worker]};
            else
              root_value[worker_root[collect_worker]] <=
                  worker_value[collect_worker];
          end
          if (collect_worker == 6'(WORKERS - 1))
            collect_worker <= 6'd0;
          else
            collect_worker <= collect_worker + 6'd1;

          // Launch at most one task per cycle.  A 32-way fill loop creates a
          // long combinational priority chain; round-robin launch costs at
          // most MAX_TASKS cycles and keeps the scheduler timing shallow.
          if ((dispatch_index < task_count) &&
              !worker_busy[dispatch_worker] &&
              !worker_start[dispatch_worker] &&
              !worker_done[dispatch_worker] &&
              !worker_pending[dispatch_worker]) begin
            worker_board[dispatch_worker] <= task_board[dispatch_index];
            worker_budget[dispatch_worker] <= task_budget[dispatch_index];
            worker_root[dispatch_worker] <= task_root[dispatch_index];
            worker_phase[dispatch_worker] <= task_phase[dispatch_index];
            worker_start[dispatch_worker] <= 1'b1;
            dispatch_index <= dispatch_index + 8'd1;
          end
          if (dispatch_worker == 6'(WORKERS - 1))
            dispatch_worker <= 6'd0;
          else
            dispatch_worker <= dispatch_worker + 6'd1;

          if ((completed_count == task_count) &&
              (dispatch_index == task_count) && all_workers_idle)
            begin
              root_direction <= 3'd0;
              state <= S_FINALIZE;
            end
        end

        S_FINALIZE: begin
          if (root_direction >= 3'd4) begin
            state <= S_CHOOSE;
          end else if (!root_valid[root_direction[1:0]] ||
                       root_tail_mode[root_direction[1:0]]) begin
            root_direction <= root_direction + 3'd1;
          end else begin
            expectation_numerator = expected_numerator_q8(
                root_sum_two[root_direction[1:0]],
                root_sum_four[root_direction[1:0]]);
            root_expected_negative <= expectation_numerator[39];
            if (expectation_numerator[39])
              root_expected_magnitude <= $unsigned(-expectation_numerator);
            else
              root_expected_magnitude <= $unsigned(expectation_numerator);
            root_expected_reciprocal <= expected_reciprocal_q24(
                root_empty_count[root_direction[1:0]]);
            state <= S_ROOT_DIV_MUL;
          end
        end

        S_ROOT_DIV_MUL: begin
          root_expected_product <=
              root_expected_magnitude * root_expected_reciprocal;
          state <= S_ROOT_DIV_STORE;
        end

        S_ROOT_DIV_STORE: begin
          if (root_expected_negative)
            root_value[root_direction[1:0]] <=
                -$signed(root_expected_product[55:24]);
          else
            root_value[root_direction[1:0]] <=
                $signed(root_expected_product[55:24]);
          root_direction <= root_direction + 3'd1;
          state <= S_FINALIZE;
        end

        S_CHOOSE: begin
          best_found = 1'b0;
          best_value = -32'sh7fff_ffff;
          best_direction = 3'd7;
          for (ff_direction_index = 0; ff_direction_index < 4;
               ff_direction_index = ff_direction_index + 1) begin
            if (root_valid[ff_direction_index] &&
                (!best_found || root_value[ff_direction_index] > best_value)) begin
              best_found = 1'b1;
              best_value = root_value[ff_direction_index];
              best_direction = ff_direction_index[2:0];
            end
          end
          move_o <= best_direction;
          busy <= 1'b0;
          done <= 1'b1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
