`timescale 1ns/1ps

module tb_search_accel #(
  parameter integer WORKERS = 32
);
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic start = 1'b0;
  logic [63:0] board_i;
  logic [15:0] budget_i;
  logic busy;
  logic done;
  logic [2:0] move_o;
  logic [63:0] cycles_o;
  logic [63:0] calls_o;
  logic [63:0] expanded_o;
  logic [63:0] cutoffs_o;
  logic overflow_o;

  integer failures = 0;
  integer move_mismatches = 0;
  integer strict_moves;
  integer test_index;
  integer timeout_cycles;
  integer vector_count;
  integer vector_file_handle;
  integer scan_fields;
  string vector_file;
  logic [63:0] boards [0:255];
  logic [2:0] expected_moves [0:255];
  logic [63:0] expected_calls [0:255];
  logic [63:0] expected_expanded [0:255];
  logic [63:0] expected_cutoffs [0:255];

  always #5 clock = ~clock;

  search_accel #(.WORKERS(WORKERS)) dut (
    .clock(clock),
    .reset(reset),
    .start(start),
    .board_i(board_i),
    .budget_i(budget_i),
    .busy(busy),
    .done(done),
    .move_o(move_o),
    .cycles_o(cycles_o),
    .calls_o(calls_o),
    .expanded_o(expanded_o),
    .cutoffs_o(cutoffs_o),
    .overflow_o(overflow_o)
  );

  initial begin
    boards[0] = 64'h0000_0000_0000_1234;
    boards[1] = 64'h0000_0102_0230_3450;
    boards[2] = 64'h0001_1223_3445_5678;
    boards[3] = 64'h1234_0234_0345_4567;
    expected_moves[0] = 3'd1;
    expected_moves[1] = 3'd2;
    expected_moves[2] = 3'd3;
    expected_moves[3] = 3'd0;
    expected_calls[0] = 64'd8238;
    expected_calls[1] = 64'd18816;
    expected_calls[2] = 64'd9638;
    expected_calls[3] = 64'd8177;
    expected_expanded[0] = 64'd1843;
    expected_expanded[1] = 64'd4414;
    expected_expanded[2] = 64'd2600;
    expected_expanded[3] = 64'd2323;
    expected_cutoffs[0] = 64'd6395;
    expected_cutoffs[1] = 64'd14402;
    expected_cutoffs[2] = 64'd7038;
    expected_cutoffs[3] = 64'd5854;
    vector_count = 4;
    strict_moves = $test$plusargs("STRICT_MOVES");

    if ($value$plusargs("VECTOR_FILE=%s", vector_file)) begin
      vector_file_handle = $fopen(vector_file, "r");
      if (vector_file_handle == 0) begin
        $display("FAIL cannot open vector file %s", vector_file);
        $finish(1);
      end
      vector_count = 0;
      while (!$feof(vector_file_handle) && vector_count < 256) begin
        scan_fields = $fscanf(vector_file_handle, "%h %d %d %d %d\n",
            boards[vector_count], expected_moves[vector_count],
            expected_calls[vector_count], expected_expanded[vector_count],
            expected_cutoffs[vector_count]);
        if (scan_fields == 5)
          vector_count = vector_count + 1;
      end
      $fclose(vector_file_handle);
      if (vector_count == 0) begin
        $display("FAIL vector file is empty %s", vector_file);
        $finish(1);
      end
      $display("Loaded %0d golden vectors from %s", vector_count, vector_file);
    end

    repeat (4) @(posedge clock);
    reset <= 1'b0;
    repeat (2) @(posedge clock);

    for (test_index = 0; test_index < vector_count; test_index = test_index + 1) begin
      board_i <= boards[test_index];
      budget_i <= 16'd500;
      start <= 1'b1;
      @(posedge clock);
      start <= 1'b0;

      timeout_cycles = 0;
      while (!done && timeout_cycles < 2000000) begin
        @(posedge clock);
        timeout_cycles = timeout_cycles + 1;
      end
      if (!done) begin
        $display("FAIL test=%0d timeout", test_index);
        failures = failures + 1;
      end else begin
        $display(
          "RESULT test=%0d board=%016h move=%0d calls=%0d expanded=%0d cutoffs=%0d cycles=%0d",
          test_index, boards[test_index], move_o, calls_o, expanded_o,
          cutoffs_o, cycles_o);
        if (move_o !== expected_moves[test_index]) begin
          $display("MOVE_MISMATCH test=%0d expected=%0d actual=%0d",
                   test_index, expected_moves[test_index], move_o);
          move_mismatches = move_mismatches + 1;
          if (strict_moves)
            failures = failures + 1;
        end
        if (calls_o !== expected_calls[test_index]) begin
          $display("FAIL test=%0d calls expected=%0d actual=%0d",
                   test_index, expected_calls[test_index], calls_o);
          failures = failures + 1;
        end
        if (expanded_o !== expected_expanded[test_index]) begin
          $display("FAIL test=%0d expanded expected=%0d actual=%0d",
                   test_index, expected_expanded[test_index], expanded_o);
          failures = failures + 1;
        end
        if (cutoffs_o !== expected_cutoffs[test_index]) begin
          $display("FAIL test=%0d cutoffs expected=%0d actual=%0d",
                   test_index, expected_cutoffs[test_index], cutoffs_o);
          failures = failures + 1;
        end
        if (overflow_o) begin
          $display("FAIL test=%0d search stack overflow", test_index);
          failures = failures + 1;
        end
      end
      repeat (2) @(posedge clock);
    end

    if (!strict_moves && move_mismatches * 10 > vector_count) begin
      $display("FAIL move agreement below 90 percent mismatches=%0d vectors=%0d",
               move_mismatches, vector_count);
      failures = failures + 1;
    end

    if (failures == 0)
      $display("PASS vectors=%0d workers=%0d move_mismatches=%0d",
               vector_count, WORKERS, move_mismatches);
    else
      $display("FAIL total=%0d", failures);
    $finish(failures != 0);
  end
endmodule
