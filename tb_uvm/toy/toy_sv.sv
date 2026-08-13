// W1 toy: verifies xsim handles SystemVerilog constructs we'll rely on —
// logic, interface, always_ff/always_comb, and a class instance.
interface toy_if(input logic clk);
  logic [7:0] data;
  logic       valid;
endinterface

class ToyItem;
  rand bit [7:0] value;
  function void show(); $display("[ToyItem] value=%0d", value); endfunction
endclass

module toy_tb;
  logic clk = 0;
  always #5 clk = ~clk;

  toy_if tif(clk);

  logic [7:0] captured;
  always_ff @(posedge clk)
    if (tif.valid) captured <= tif.data;

  logic [8:0] sum;
  always_comb sum = captured + 8'd1;

  initial begin
    ToyItem it = new();
    void'(it.randomize());
    it.show();
    tif.valid = 0;
    @(posedge clk);
    tif.data  = it.value;
    tif.valid = 1;
    @(posedge clk); #1;
    tif.valid = 0;
    if (captured === it.value && sum === captured + 1)
      $display("TOY PASS: captured=%0d sum=%0d", captured, sum);
    else
      $fatal(1, "TOY FAIL: captured=%0d expected=%0d", captured, it.value);
    $finish;
  end
endmodule
