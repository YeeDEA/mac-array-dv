`timescale 1ns/1ps
// Bus-functional interface for mac_array_4x4 (UVM driver/monitor attach point).
interface mac_if (input logic clk, input logic rst_n);
  logic         in_valid;
  logic         in_ready;
  logic         in_last;
  logic [31:0]  a_col;
  logic [31:0]  b_row;
  logic         out_valid;
  logic         out_ready;
  logic         out_last;
  logic [1:0]   out_row;
  logic [127:0] c_row;
endinterface
