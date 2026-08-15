`timescale 1ns/1ps

module search_worker #(
  parameter integer STACK_DEPTH = 24
) (
  input  logic         clock,
  input  logic         reset,
  input  logic         start,
  input  logic [63:0]  board_i,
  input  logic [4:0]   depth_i,
  input  logic [15:0]  budget_i,
  output logic         busy,
  output logic         done,
  output logic signed [31:0] value_o,
  output logic [31:0]  calls_o,
  output logic [31:0]  expanded_o,
  output logic [31:0]  cutoffs_o,
  output logic         overflow_o
);
  import game2048_pkg::*;

  localparam logic [3:0] S_IDLE       = 4'd0;
  localparam logic [3:0] S_ENTER_MAX  = 4'd1;
  localparam logic [3:0] S_MAX_DIR    = 4'd2;
  localparam logic [3:0] S_ENTER_EXP  = 4'd3;
  localparam logic [3:0] S_EXP_NEXT   = 4'd4;
  localparam logic [3:0] S_RETURN     = 4'd5;
  localparam logic [3:0] S_EXP_MUL    = 4'd6;
  localparam logic [3:0] S_EXP_RESULT = 4'd7;

  logic [3:0] state;
  logic [63:0] current_board;
  logic signed [5:0] current_depth;
  logic [15:0] current_remaining;

  logic [2:0] current_direction;
  logic signed [31:0] current_best;
  logic current_has_best;

  logic [15:0] current_empty_mask;
  logic [4:0] current_empty_count;
  logic [15:0] current_spawn_budget;
  logic [4:0] current_cursor;
  logic current_phase;
  logic signed [35:0] current_sum_two;
  logic signed [35:0] current_sum_four;

  logic expected_negative;
  logic [39:0] expected_magnitude;
  logic [23:0] expected_reciprocal;
  (* use_dsp = "yes" *) logic [63:0] expected_product;

  logic signed [31:0] return_value;
  logic [15:0] return_remaining;

  logic [4:0] stack_pointer;
  logic frame_kind [0:STACK_DEPTH-1];
  logic [63:0] frame_board [0:STACK_DEPTH-1];
  logic signed [5:0] frame_depth [0:STACK_DEPTH-1];
  logic [15:0] frame_remaining [0:STACK_DEPTH-1];
  logic [4:0] frame_cursor [0:STACK_DEPTH-1];
  logic frame_phase [0:STACK_DEPTH-1];
  logic frame_has_best [0:STACK_DEPTH-1];
  logic signed [31:0] frame_best [0:STACK_DEPTH-1];
  logic [15:0] frame_empty_mask [0:STACK_DEPTH-1];
  logic [4:0] frame_empty_count [0:STACK_DEPTH-1];
  logic [15:0] frame_spawn_budget [0:STACK_DEPTH-1];
  logic signed [35:0] frame_sum_two [0:STACK_DEPTH-1];
  logic signed [35:0] frame_sum_four [0:STACK_DEPTH-1];

  logic [63:0] direction_board;
  logic [15:0] board_empty_mask;
  logic [4:0] board_empty_count;
  logic [4:0] next_empty_cell;
  integer scan_cell;

  always_comb begin
    direction_board = move_dir(current_board, current_direction[1:0]);
    board_empty_mask = empty_mask(current_board);
    board_empty_count = count_empty(current_board);
    next_empty_cell = 5'd31;
    for (scan_cell = 0; scan_cell < 16; scan_cell = scan_cell + 1)
      if ((scan_cell >= current_cursor) && current_empty_mask[scan_cell] &&
          (next_empty_cell == 5'd31))
        next_empty_cell = scan_cell[4:0];
  end

  always_ff @(posedge clock) begin : worker_fsm
    integer frame_index;
    logic [15:0] remaining_after_entry;
    logic [15:0] spawn_budget;
    logic signed [31:0] updated_value;
    logic signed [39:0] expectation_numerator;

    done <= 1'b0;
    if (reset) begin
      state <= S_IDLE;
      busy <= 1'b0;
      done <= 1'b0;
      value_o <= 32'sd0;
      calls_o <= 32'd0;
      expanded_o <= 32'd0;
      cutoffs_o <= 32'd0;
      overflow_o <= 1'b0;
      stack_pointer <= 5'd0;
    end else begin
      case (state)
        S_IDLE: begin
          if (start) begin
            busy <= 1'b1;
            current_board <= board_i;
            current_depth <= $signed({1'b0, depth_i});
            current_remaining <= budget_i;
            calls_o <= 32'd0;
            expanded_o <= 32'd0;
            cutoffs_o <= 32'd0;
            overflow_o <= 1'b0;
            stack_pointer <= 5'd0;
            state <= S_ENTER_MAX;
          end
        end

        S_ENTER_MAX: begin
          calls_o <= calls_o + 32'd1;
          if (current_remaining == 16'd0) begin
            cutoffs_o <= cutoffs_o + 32'd1;
            return_value <= eval_simple_q8(current_board);
            return_remaining <= 16'd0;
            state <= S_RETURN;
          end else begin
            remaining_after_entry = current_remaining - 16'd1;
            expanded_o <= expanded_o + 32'd1;
            current_remaining <= remaining_after_entry;
            if (board_game_over(current_board)) begin
              return_value <= eval_simple_q8(current_board) - GAME_OVER_PENALTY_Q8;
              return_remaining <= remaining_after_entry;
              state <= S_RETURN;
            end else if (current_depth == 6'sd0) begin
              return_value <= eval_simple_q8(current_board);
              return_remaining <= remaining_after_entry;
              state <= S_RETURN;
            end else begin
              current_direction <= 3'd0;
              current_best <= -32'sh7fff_ffff;
              current_has_best <= 1'b0;
              state <= S_MAX_DIR;
            end
          end
        end

        S_MAX_DIR: begin
          if (current_direction >= 3'd4) begin
            if (current_has_best)
              return_value <= current_best;
            else
              return_value <= eval_simple_q8(current_board) - GAME_OVER_PENALTY_Q8;
            return_remaining <= current_remaining;
            state <= S_RETURN;
          end else if (direction_board == current_board) begin
            current_direction <= current_direction + 3'd1;
          end else if (stack_pointer >= 5'(STACK_DEPTH)) begin
            overflow_o <= 1'b1;
            return_value <= eval_simple_q8(current_board);
            return_remaining <= current_remaining;
            state <= S_RETURN;
          end else begin
            frame_kind[stack_pointer] <= 1'b0;
            frame_board[stack_pointer] <= current_board;
            frame_depth[stack_pointer] <= current_depth;
            frame_cursor[stack_pointer] <= {2'd0, current_direction} + 5'd1;
            frame_has_best[stack_pointer] <= current_has_best;
            frame_best[stack_pointer] <= current_best;
            stack_pointer <= stack_pointer + 5'd1;

            current_board <= direction_board;
            current_remaining <= current_remaining;
            state <= S_ENTER_EXP;
          end
        end

        S_ENTER_EXP: begin
          calls_o <= calls_o + 32'd1;
          if (current_remaining == 16'd0) begin
            cutoffs_o <= cutoffs_o + 32'd1;
            return_value <= eval_simple_q8(current_board);
            return_remaining <= 16'd0;
            state <= S_RETURN;
          end else begin
            remaining_after_entry = current_remaining - 16'd1;
            expanded_o <= expanded_o + 32'd1;
            current_remaining <= remaining_after_entry;
            if (board_empty_count == 5'd0) begin
              current_depth <= current_depth - 6'sd1;
              state <= S_ENTER_MAX;
            end else if (current_depth <= 6'sd0) begin
              return_value <= eval_simple_q8(current_board);
              return_remaining <= remaining_after_entry;
              state <= S_RETURN;
            end else begin
              spawn_budget = remaining_after_entry /
                  ({11'd0, board_empty_count} << 1);
              if (spawn_budget == 16'd0)
                spawn_budget = 16'd1;
              current_empty_mask <= board_empty_mask;
              current_empty_count <= board_empty_count;
              current_spawn_budget <= spawn_budget;
              current_cursor <= 5'd0;
              current_phase <= 1'b0;
              current_sum_two <= 36'sd0;
              current_sum_four <= 36'sd0;
              state <= S_EXP_NEXT;
            end
          end
        end

        S_EXP_NEXT: begin
          if (next_empty_cell == 5'd31) begin
            if (!current_phase) begin
              current_phase <= 1'b1;
              current_cursor <= 5'd0;
            end else begin
              expectation_numerator = expected_numerator_q8(
                  current_sum_two, current_sum_four);
              expected_negative <= expectation_numerator[39];
              if (expectation_numerator[39])
                expected_magnitude <= $unsigned(-expectation_numerator);
              else
                expected_magnitude <= $unsigned(expectation_numerator);
              expected_reciprocal <=
                  expected_reciprocal_q24(current_empty_count);
              state <= S_EXP_MUL;
            end
          end else if (stack_pointer >= 5'(STACK_DEPTH)) begin
            overflow_o <= 1'b1;
            return_value <= eval_simple_q8(current_board);
            return_remaining <= current_remaining;
            state <= S_RETURN;
          end else begin
            frame_kind[stack_pointer] <= 1'b1;
            frame_board[stack_pointer] <= current_board;
            frame_depth[stack_pointer] <= current_depth;
            frame_remaining[stack_pointer] <= current_remaining;
            frame_cursor[stack_pointer] <= next_empty_cell + 5'd1;
            frame_phase[stack_pointer] <= current_phase;
            frame_empty_mask[stack_pointer] <= current_empty_mask;
            frame_empty_count[stack_pointer] <= current_empty_count;
            frame_spawn_budget[stack_pointer] <= current_spawn_budget;
            frame_sum_two[stack_pointer] <= current_sum_two;
            frame_sum_four[stack_pointer] <= current_sum_four;
            stack_pointer <= stack_pointer + 5'd1;

            current_board <= set_spawn(
                current_board, next_empty_cell[3:0],
                current_phase ? 2'd2 : 2'd1);
            current_depth <= current_depth - 6'sd1;
            current_remaining <= current_spawn_budget;
            state <= S_ENTER_MAX;
          end
        end

        S_EXP_MUL: begin
          expected_product <= expected_magnitude * expected_reciprocal;
          state <= S_EXP_RESULT;
        end

        S_EXP_RESULT: begin
          if (expected_negative)
            return_value <= -$signed(expected_product[55:24]);
          else
            return_value <= $signed(expected_product[55:24]);
          return_remaining <= current_remaining;
          state <= S_RETURN;
        end

        S_RETURN: begin
          if (stack_pointer == 5'd0) begin
            value_o <= return_value;
            busy <= 1'b0;
            done <= 1'b1;
            state <= S_IDLE;
          end else begin
            frame_index = {27'd0, stack_pointer} - 1;
            stack_pointer <= stack_pointer - 5'd1;
            if (!frame_kind[frame_index]) begin
              current_board <= frame_board[frame_index];
              current_depth <= frame_depth[frame_index];
              current_remaining <= return_remaining;
              current_direction <= frame_cursor[frame_index][2:0];
              if (!frame_has_best[frame_index] ||
                  (return_value > frame_best[frame_index])) begin
                current_best <= return_value;
                current_has_best <= 1'b1;
              end else begin
                current_best <= frame_best[frame_index];
                current_has_best <= frame_has_best[frame_index];
              end
              state <= S_MAX_DIR;
            end else begin
              current_board <= frame_board[frame_index];
              current_depth <= frame_depth[frame_index];
              current_remaining <= frame_remaining[frame_index];
              current_cursor <= frame_cursor[frame_index];
              current_phase <= frame_phase[frame_index];
              current_empty_mask <= frame_empty_mask[frame_index];
              current_empty_count <= frame_empty_count[frame_index];
              current_spawn_budget <= frame_spawn_budget[frame_index];
              updated_value = return_value;
              if (!frame_phase[frame_index]) begin
                current_sum_two <= frame_sum_two[frame_index] +
                    {{4{updated_value[31]}}, updated_value};
                current_sum_four <= frame_sum_four[frame_index];
              end else begin
                current_sum_two <= frame_sum_two[frame_index];
                current_sum_four <= frame_sum_four[frame_index] +
                    {{4{updated_value[31]}}, updated_value};
              end
              state <= S_EXP_NEXT;
            end
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
