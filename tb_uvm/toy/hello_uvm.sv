// W1 bonus: pre-flight for the W7 risk — does xsim's built-in UVM 1.2 work?
// Compile: xvlog -sv -L uvm hello_uvm.sv
// Elab:    xelab hello_tb -L uvm -s hello_sim
// Run:     xsim hello_sim -runall
import uvm_pkg::*;
`include "uvm_macros.svh"

class hello_test extends uvm_test;
  `uvm_component_utils(hello_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("HELLO", "UVM 1.2 is alive on xsim", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass

module hello_tb;
  initial run_test("hello_test");
endmodule
