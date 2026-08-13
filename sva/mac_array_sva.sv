`timescale 1ns/1ps
// Protocol + data-integrity assertions for mac_array_4x4 (attached via bind, sees internals).
// xsim 2020.2 limitations found: no "default disable iff", no $past/$stable in properties.
// Workaround: explicit per-property disable iff + hand-rolled previous-cycle sample registers.
module mac_array_sva (
  input logic clk, rst_n,
  input logic in_valid, in_ready, in_last,
  input logic [31:0] a_col, b_row,
  input logic out_valid, out_ready, out_last,
  input logic [1:0] out_row,
  input logic [127:0] c_row,
  input logic en, clr,
  input logic signed [31:0] acc [4][4]
);
  logic [511:0] acc_flat;
  always_comb
    for (int i = 0; i < 4; i++)
      for (int j = 0; j < 4; j++)
        acc_flat[(4*i+j)*32 +: 32] = acc[i][j];

  // previous-cycle samples (replacement for unsupported $past/$stable)
  logic [127:0] c_row_q;
  logic [1:0]   out_row_q;
  logic [511:0] acc_flat_q;
  logic [64:0]  in_bus_q;
  wire  [64:0]  in_bus = {a_col, b_row, in_last};
  always_ff @(posedge clk) begin
    c_row_q    <= c_row;
    out_row_q  <= out_row;
    acc_flat_q <= acc_flat;
    in_bus_q   <= in_bus;
  end

  // A1: input side blocked while draining
  a_drain_blocks_in: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid |-> !in_ready);
  // A2: output data/row held while stalled
  a_out_stable: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid && !out_ready |=> out_valid && c_row == c_row_q && out_row == out_row_q);
  // A3: out_row increments per accepted drain beat
  a_row_inc: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid && out_ready && !out_last |=> out_row == 2'(out_row_q + 1));
  // A4: out_last exactly on row 3
  a_out_last_iff_row3: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid |-> (out_last == (out_row == 2'd3)));
  // A5: accumulators change only on accepted beat or clear
  a_acc_stable_when_idle: assert property (@(posedge clk) disable iff (!rst_n)
    !en && !clr |=> acc_flat == acc_flat_q);
  // A6: accumulate exactly on accepted input beat
  a_en_iff_accept: assert property (@(posedge clk) disable iff (!rst_n)
    en == (in_valid && in_ready));
  // A7: tile boundary clears every accumulator
  a_tile_clear: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid && out_ready && out_last |=> acc_flat == '0);
  // A8: environment holds input stable during stall
  a_in_stable: assert property (@(posedge clk) disable iff (!rst_n)
    in_valid && !in_ready |=> in_valid && in_bus == in_bus_q);
  // A9: reset clears accumulators (not disabled by reset itself)
  a_reset_clear: assert property (@(posedge clk)
    !rst_n |=> acc_flat == '0);
endmodule
