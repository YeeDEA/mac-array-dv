`timescale 1ns/1ps
// Bus-functional interface for mac_array_4x4 (UVM driver/monitor attach point).
interface mac_if #(parameter int N = 4) (input logic clk, input logic rst_n);
  localparam int RW = $clog2(N);
  logic         in_valid;
  logic         in_ready;
  logic         in_last;
  logic [8*N-1:0]  a_col;
  logic [8*N-1:0]  b_row;
  logic         out_valid;
  logic         out_ready;
  logic         out_last;
  logic [RW-1:0]   out_row;
  logic [32*N-1:0] c_row;
endinterface
