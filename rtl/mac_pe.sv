`timescale 1ns/1ps
// Processing element: acc += a*b (signed INT8), sync reset, clr > en priority.
module mac_pe #(parameter int ACC_W = 32) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    clr,
  input  logic                    en,
  input  logic signed [7:0]       a,
  input  logic signed [7:0]       b,
  output logic signed [ACC_W-1:0] acc
);
  logic signed [15:0] prod;
`ifdef BUG4
  assign prod = a * signed'({1'b0, b}); // BUG4: b zero-extended (treated unsigned)
`else
  assign prod = a * b;
`endif

  always_ff @(posedge clk) begin
    if (!rst_n)   acc <= '0;
    else if (clr) acc <= '0;
    else if (en) begin
`ifdef BUG1
      acc <= ACC_W'(signed'(16'(acc + prod))); // BUG1: accumulator wraps at 16 bits
`else
      acc <= acc + prod;
`endif
    end
  end
endmodule
