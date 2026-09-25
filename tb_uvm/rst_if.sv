`timescale 1ns/1ps
// Testbench-side reset request. tb_top ANDs it into the power-on reset, so a test can pulse
// rst_n in the middle of a tile or a drain (mac_reset_test) without touching the DUT ports.
interface rst_if (input logic clk);
  logic rst_req = 1'b0;   // 1 = hold the DUT in reset
endinterface
