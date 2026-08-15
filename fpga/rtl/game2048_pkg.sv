`timescale 1ns/1ps

package game2048_pkg;
  localparam logic signed [31:0] GAME_OVER_PENALTY_Q8 =
      32'sd1000000 <<< 8;

  function automatic logic [15:0] reverse_row(input logic [15:0] row);
    reverse_row = {row[3:0], row[7:4], row[11:8], row[15:12]};
  endfunction

  function automatic logic [15:0] move_row_left(input logic [15:0] row);
    logic [3:0] compact [0:4];
    logic [3:0] merged [0:3];
    integer read_index;
    integer compact_count;
    integer write_index;
    logic skip_next;
    begin
      for (read_index = 0; read_index < 4; read_index = read_index + 1) begin
        compact[read_index] = 4'd0;
        merged[read_index] = 4'd0;
      end
      compact[4] = 4'd0;

      compact_count = 0;
      for (read_index = 0; read_index < 4; read_index = read_index + 1) begin
        if (row[read_index * 4 +: 4] != 4'd0) begin
          compact[compact_count] = row[read_index * 4 +: 4];
          compact_count = compact_count + 1;
        end
      end

      write_index = 0;
      skip_next = 1'b0;
      for (read_index = 0; read_index < 4; read_index = read_index + 1) begin
        if (skip_next) begin
          skip_next = 1'b0;
        end else if ((read_index + 1 < compact_count) &&
                     (compact[read_index] == compact[read_index + 1])) begin
          merged[write_index] = compact[read_index] + 4'd1;
          write_index = write_index + 1;
          skip_next = 1'b1;
        end else if (read_index < compact_count) begin
          merged[write_index] = compact[read_index];
          write_index = write_index + 1;
        end
      end

      move_row_left = {
        merged[3], merged[2], merged[1], merged[0]
      };
    end
  endfunction

  function automatic logic [15:0] move_row_right(input logic [15:0] row);
    move_row_right = reverse_row(move_row_left(reverse_row(row)));
  endfunction

  function automatic logic [63:0] transpose_board(input logic [63:0] board);
    logic [63:0] result;
    integer row;
    integer column;
    begin
      result = 64'd0;
      for (row = 0; row < 4; row = row + 1)
        for (column = 0; column < 4; column = column + 1)
          result[(column * 4 + row) * 4 +: 4] =
              board[(row * 4 + column) * 4 +: 4];
      transpose_board = result;
    end
  endfunction

  function automatic logic [63:0] move_left(input logic [63:0] board);
    logic [63:0] result;
    integer row;
    begin
      result = 64'd0;
      for (row = 0; row < 4; row = row + 1)
        result[row * 16 +: 16] = move_row_left(board[row * 16 +: 16]);
      move_left = result;
    end
  endfunction

  function automatic logic [63:0] move_right(input logic [63:0] board);
    logic [63:0] result;
    integer row;
    begin
      result = 64'd0;
      for (row = 0; row < 4; row = row + 1)
        result[row * 16 +: 16] = move_row_right(board[row * 16 +: 16]);
      move_right = result;
    end
  endfunction

  function automatic logic [63:0] move_up(input logic [63:0] board);
    move_up = transpose_board(move_left(transpose_board(board)));
  endfunction

  function automatic logic [63:0] move_down(input logic [63:0] board);
    move_down = transpose_board(move_right(transpose_board(board)));
  endfunction

  function automatic logic [63:0] move_dir(
      input logic [63:0] board,
      input logic [1:0] direction
  );
    case (direction)
      2'd0: move_dir = move_up(board);
      2'd1: move_dir = move_down(board);
      2'd2: move_dir = move_left(board);
      default: move_dir = move_right(board);
    endcase
  endfunction

  function automatic logic [15:0] empty_mask(input logic [63:0] board);
    logic [15:0] mask;
    integer cell_index;
    begin
      mask = 16'd0;
      for (cell_index = 0; cell_index < 16; cell_index = cell_index + 1)
        mask[cell_index] = board[cell_index * 4 +: 4] == 4'd0;
      empty_mask = mask;
    end
  endfunction

  function automatic logic [4:0] count_empty(input logic [63:0] board);
    logic [4:0] count;
    integer cell_index;
    begin
      count = 5'd0;
      for (cell_index = 0; cell_index < 16; cell_index = cell_index + 1)
        if (board[cell_index * 4 +: 4] == 4'd0)
          count = count + 5'd1;
      count_empty = count;
    end
  endfunction

  function automatic logic board_game_over(input logic [63:0] board);
    logic merge_available;
    integer row;
    integer column;
    begin
      if (count_empty(board) != 5'd0) begin
        board_game_over = 1'b0;
      end else begin
        merge_available = 1'b0;
        for (row = 0; row < 4; row = row + 1) begin
          for (column = 0; column < 3; column = column + 1) begin
            if (board[(row * 4 + column) * 4 +: 4] ==
                board[(row * 4 + column + 1) * 4 +: 4])
              merge_available = 1'b1;
          end
        end
        for (row = 0; row < 3; row = row + 1) begin
          for (column = 0; column < 4; column = column + 1) begin
            if (board[(row * 4 + column) * 4 +: 4] ==
                board[((row + 1) * 4 + column) * 4 +: 4])
              merge_available = 1'b1;
          end
        end
        board_game_over = !merge_available;
      end
    end
  endfunction

  function automatic logic signed [31:0] eval_simple_q8(
      input logic [63:0] board
  );
    logic [4:0] empties;
    logic [3:0] maximum;
    logic [5:0] score;
    integer cell_index;
    begin
      empties = count_empty(board);
      maximum = 4'd0;
      for (cell_index = 0; cell_index < 16; cell_index = cell_index + 1)
        if (board[cell_index * 4 +: 4] > maximum)
          maximum = board[cell_index * 4 +: 4];
      score = {1'b0, empties} + {2'b00, maximum};
      eval_simple_q8 = $signed({18'd0, score, 8'd0});
    end
  endfunction

  function automatic logic signed [39:0] expected_numerator_q8(
      input logic signed [35:0] sum_two,
      input logic signed [35:0] sum_four
  );
    logic signed [39:0] numerator;
    begin
      numerator = $signed(sum_two) * 40'sd9 +
          $signed({{4{sum_four[35]}}, sum_four});
      expected_numerator_q8 = numerator;
    end
  endfunction

  // Search values use eight fractional bits.  The Q24 reciprocal keeps the
  // division error below one Q8 LSB for all non-terminal heuristic values.
  // Terminal values remain separated by the much larger game-over penalty.
  // The search only divides by these
  // sixteen denominators.  A reciprocal multiply avoids a large variable
  // divider in the timing-critical recursive worker.
  function automatic logic [23:0] expected_reciprocal_q24(
      input logic [4:0] empty_count
  );
    begin
      case (empty_count)
        5'd1:  expected_reciprocal_q24 = 24'h19_9999;
        5'd2:  expected_reciprocal_q24 = 24'h0c_cccc;
        5'd3:  expected_reciprocal_q24 = 24'h08_8888;
        5'd4:  expected_reciprocal_q24 = 24'h06_6666;
        5'd5:  expected_reciprocal_q24 = 24'h05_1eb8;
        5'd6:  expected_reciprocal_q24 = 24'h04_4444;
        5'd7:  expected_reciprocal_q24 = 24'h03_a83a;
        5'd8:  expected_reciprocal_q24 = 24'h03_3333;
        5'd9:  expected_reciprocal_q24 = 24'h02_d82d;
        5'd10: expected_reciprocal_q24 = 24'h02_8f5c;
        5'd11: expected_reciprocal_q24 = 24'h02_53c8;
        5'd12: expected_reciprocal_q24 = 24'h02_2222;
        5'd13: expected_reciprocal_q24 = 24'h01_f81f;
        5'd14: expected_reciprocal_q24 = 24'h01_d41d;
        5'd15: expected_reciprocal_q24 = 24'h01_b4e8;
        5'd16: expected_reciprocal_q24 = 24'h01_9999;
        default: expected_reciprocal_q24 = 24'd0;
      endcase
    end
  endfunction

  function automatic logic [63:0] set_spawn(
      input logic [63:0] board,
      input logic [3:0] cell_index,
      input logic [1:0] value
  );
    logic [63:0] result;
    begin
      result = board;
      result[cell_index * 4 +: 4] = {2'd0, value};
      set_spawn = result;
    end
  endfunction

  function automatic logic [31:0] lfsr_next32(input logic [31:0] value);
    logic feedback;
    logic [31:0] result;
    begin
      feedback = value[31] ^ value[21] ^ value[1] ^ value[0];
      result = {value[30:0], feedback};
      if (result == 32'd0)
        result = 32'h1;
      lfsr_next32 = result;
    end
  endfunction

  // Largest multiple of count not greater than sixteen.  Rejection above
  // this limit makes a four-bit sample uniform for every empty-cell count.
  function automatic logic [4:0] random_rejection_limit(
      input logic [4:0] count
  );
    begin
      case (count)
        5'd1, 5'd2, 5'd4, 5'd8, 5'd16: random_rejection_limit = 5'd16;
        5'd3, 5'd5, 5'd15:              random_rejection_limit = 5'd15;
        5'd6, 5'd12:                    random_rejection_limit = 5'd12;
        5'd7, 5'd14:                    random_rejection_limit = 5'd14;
        5'd9:                            random_rejection_limit = 5'd9;
        5'd10:                           random_rejection_limit = 5'd10;
        5'd11:                           random_rejection_limit = 5'd11;
        5'd13:                           random_rejection_limit = 5'd13;
        default:                         random_rejection_limit = 5'd0;
      endcase
    end
  endfunction

  function automatic logic [3:0] accepted_empty_rank(
      input logic [3:0] candidate,
      input logic [4:0] count
  );
    begin
      case (count)
        5'd1: accepted_empty_rank = 4'd0;
        5'd2: accepted_empty_rank = {3'd0, candidate[0]};
        5'd3: begin
          if (candidate >= 4'd12) accepted_empty_rank = candidate - 4'd12;
          else if (candidate >= 4'd9) accepted_empty_rank = candidate - 4'd9;
          else if (candidate >= 4'd6) accepted_empty_rank = candidate - 4'd6;
          else if (candidate >= 4'd3) accepted_empty_rank = candidate - 4'd3;
          else accepted_empty_rank = candidate;
        end
        5'd4: accepted_empty_rank = {2'd0, candidate[1:0]};
        5'd5: begin
          if (candidate >= 4'd10) accepted_empty_rank = candidate - 4'd10;
          else if (candidate >= 4'd5) accepted_empty_rank = candidate - 4'd5;
          else accepted_empty_rank = candidate;
        end
        5'd6: accepted_empty_rank =
            candidate >= 4'd6 ? candidate - 4'd6 : candidate;
        5'd7: accepted_empty_rank =
            candidate >= 4'd7 ? candidate - 4'd7 : candidate;
        5'd8: accepted_empty_rank = {1'd0, candidate[2:0]};
        default: accepted_empty_rank = candidate;
      endcase
    end
  endfunction

  function automatic logic [4:0] select_empty_by_rank(
      input logic [63:0] board,
      input logic [3:0] rank
  );
    logic [4:0] selected;
    logic [4:0] seen;
    integer cell_index;
    begin
      selected = 5'd31;
      seen = 5'd0;
      for (cell_index = 0; cell_index < 16; cell_index = cell_index + 1) begin
        if (board[cell_index * 4 +: 4] == 4'd0) begin
          if ((seen == {1'b0, rank}) && (selected == 5'd31))
            selected = cell_index[4:0];
          seen = seen + 5'd1;
        end
      end
      select_empty_by_rank = selected;
    end
  endfunction

  function automatic logic [3:0] highest_tile_exponent(
      input logic [63:0] board
  );
    logic [3:0] highest;
    integer cell_index;
    begin
      highest = 4'd0;
      for (cell_index = 0; cell_index < 16; cell_index = cell_index + 1)
        if (board[cell_index * 4 +: 4] > highest)
          highest = board[cell_index * 4 +: 4];
      highest_tile_exponent = highest;
    end
  endfunction
endpackage
