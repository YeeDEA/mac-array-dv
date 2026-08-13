`timescale 1ns/1ps
// 4x4 output-stationary MAC array. Beat k: a_col = column k of A, b_row = row k of B.
// Drain: c_row presents C[out_row][0..3] as 4 x INT32 lanes.
module mac_array_4x4 #(parameter int ACC_W = 32) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         in_valid,
  input  logic         in_last,
  output logic         in_ready,
  input  logic [31:0]  a_col,   // lane i = A[i][k], signed INT8
  input  logic [31:0]  b_row,   // lane j = B[k][j], signed INT8
  output logic         out_valid,
  input  logic         out_ready,
  output logic         out_last,
  output logic [1:0]   out_row,
  output logic [127:0] c_row    // lane j = C[out_row][j], signed INT32
);
  logic en, clr;

  ctrl u_ctrl (
    .clk, .rst_n, .in_valid, .in_last, .in_ready,
    .out_ready, .out_valid, .out_last, .out_row, .en, .clr
  );

  logic signed [ACC_W-1:0] acc [4][4];

`ifdef BUG3
  localparam bit BUG3_ON = 1'b1; // BUG3: PE(2,3) never clears between tiles
`else
  localparam bit BUG3_ON = 1'b0;
`endif

  for (genvar i = 0; i < 4; i++) begin : g_row
    for (genvar j = 0; j < 4; j++) begin : g_col
      mac_pe #(.ACC_W(ACC_W)) u_pe (
        .clk, .rst_n,
        .clr ((BUG3_ON && i == 2 && j == 3) ? 1'b0 : clr),
        .en,
        .a   (a_col[8*i +: 8]),
        .b   (b_row[8*j +: 8]),
        .acc (acc[i][j])
      );
    end
  end

  always_comb begin
    for (int j = 0; j < 4; j++) c_row[32*j +: 32] = acc[out_row][j];
  end
endmodule
