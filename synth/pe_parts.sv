// Component split of mac_pe for the synthesis breakdown (docs/synth_report.md).
// Each module is exactly one piece of rtl/mac_pe.sv, synthesized on its own so the cell
// count can be attributed: multiplier vs accumulator adder vs accumulator register.
module pe_mul (input logic signed [7:0] a, b, output logic signed [15:0] prod);
  assign prod = a * b;                         // same expression as mac_pe
endmodule

module pe_add (input logic signed [31:0] acc, input logic signed [15:0] prod,
               output logic signed [31:0] sum);
  assign sum = acc + prod;                     // sign-extending 32 + 16 add, as in mac_pe
endmodule

module pe_reg (input logic clk, rst_n, clr, en, input logic signed [31:0] d,
               output logic signed [31:0] q);
  always_ff @(posedge clk)                     // same reset/clr/en priority as mac_pe
    if (!rst_n) q <= '0; else if (clr) q <= '0; else if (en) q <= d;
endmodule
