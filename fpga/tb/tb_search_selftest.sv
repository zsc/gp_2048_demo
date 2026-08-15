`timescale 1ns/1ps

module tb_search_selftest;
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [511:0] status;
  integer timeout_cycles;

  always #5 clock = ~clock;

  search_xcku115_selftest_top #(
    .WORKERS(32),
    .VECTOR_COUNT(64)
  ) dut (
    .sim_clk(clock),
    .sim_reset(reset),
    .sim_status(status)
  );

  initial begin
    repeat (4) @(posedge clock);
    reset <= 1'b0;
    timeout_cycles = 0;
    while (!status[40] && timeout_cycles < 2000000) begin
      @(posedge clock);
      timeout_cycles = timeout_cycles + 1;
    end

    $display(
      "SELFTEST done=%0d pass=%0d timeout=%0d overflow=%0d completed=%0d move_mismatches=%0d metric_mismatches=%0d wall_cycles=%0d total_search_cycles=%0d max_search_cycles=%0d",
      status[40], status[41], status[42], status[43], status[62:55],
      status[70:63], status[86:71], status[148:117], status[212:149],
      status[276:213]);
    if (!status[40] || !status[41]) begin
      $display("FAIL autonomous XCKU115 self-test");
      $finish(1);
    end
    $display("PASS autonomous XCKU115 self-test");
    $finish;
  end
endmodule
