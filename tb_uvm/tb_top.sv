`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  import mac_pkg::*;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;
  initial begin
    repeat (4) @(negedge clk);
    rst_n = 1;
  end

  mac_if ifc (clk, rst_n);

  mac_array_4x4 dut (
    .clk, .rst_n,
    .in_valid (ifc.in_valid),
    .in_last  (ifc.in_last),
    .in_ready (ifc.in_ready),
    .a_col    (ifc.a_col),
    .b_row    (ifc.b_row),
    .out_valid(ifc.out_valid),
    .out_ready(ifc.out_ready),
    .out_last (ifc.out_last),
    .out_row  (ifc.out_row),
    .c_row    (ifc.c_row)
  );

  initial begin
    uvm_config_db#(virtual mac_if)::set(null, "*", "vif", ifc);
    run_test();
  end

`ifdef DUMP
  initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
  end
`endif
endmodule
