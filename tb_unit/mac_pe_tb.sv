`timescale 1ns/1ps
// W2 directed self-checking TB for mac_pe: sign corners, boundaries, 1000 randoms.
module mac_pe_tb;
  logic clk = 0, rst_n = 0, clr = 0, en = 0;
  logic signed [7:0] a = '0, b = '0;
  logic signed [31:0] acc;
  int n_checks = 0;
  int acc_ref = 0;

  mac_pe dut (.*);
  always #5 clk = ~clk;

  task automatic step(input logic t_en, input logic t_clr, input byte ta, input byte tb_v);
    @(negedge clk);
    en <= t_en; clr <= t_clr; a <= ta; b <= tb_v;
    @(negedge clk);
    en <= 0; clr <= 0;
    if (t_clr)      acc_ref = 0;
    else if (t_en)  acc_ref = acc_ref + int'(ta) * int'(tb_v);
    if (acc !== acc_ref)
      $fatal(1, "MISMATCH acc=%0d ref=%0d (a=%0d b=%0d en=%b clr=%b)", acc, acc_ref, ta, tb_v, t_en, t_clr);
    n_checks++;
  endtask

  byte corners [6] = '{-128, -127, -1, 0, 1, 127};

  initial begin
    repeat (3) @(negedge clk);
    rst_n <= 1;
    @(negedge clk);
    if (acc !== 0) $fatal(1, "acc not zero after reset");

    // every sign/boundary product from a cleared accumulator
    foreach (corners[x]) foreach (corners[y]) begin
      step(0, 1, 0, 0);
      step(1, 0, corners[x], corners[y]);
    end

    // long accumulation runs with random clears / idle cycles
    step(0, 1, 0, 0);
    repeat (1000) begin
      byte ra, rb;
      logic re, rc;
      ra = byte'($urandom);
      rb = byte'($urandom);
      re = ($urandom_range(0, 9) != 0);
      rc = ($urandom_range(0, 19) == 0);
      step(re, rc, ra, rb);
    end

    $display("MAC_PE TB PASS: %0d checks", n_checks);
    $finish;
  end
endmodule
