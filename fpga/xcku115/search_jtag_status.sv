`timescale 1ns/1ps

module search_jtag_status #(
  parameter integer WIDTH = 512
) (
  input logic [WIDTH-1:0] status_i
);
`ifdef SIM
  logic unused;
  assign unused = ^status_i;
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

  always @(posedge drck) begin
    if (sel && capture)
      shift_data <= status_i;
    else if (sel && shift)
      shift_data <= {tdi, shift_data[WIDTH-1:1]};
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

  wire unused = reset ^ runtest ^ tck ^ tms ^ update;
`endif
endmodule
