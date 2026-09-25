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
  input logic signed [31:0] acc [4][4],
  input logic       state,        // ctrl FSM: 0 = S_ACCEPT, 1 = S_DRAIN
  input logic [1:0] row           // ctrl drain row counter
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
  logic [31:0]  a_col_q, b_row_q;
  logic         en_q, clr_q;
  wire  [64:0]  in_bus = {a_col, b_row, in_last};
  always_ff @(posedge clk) begin
    c_row_q    <= c_row;
    out_row_q  <= out_row;
    acc_flat_q <= acc_flat;
    in_bus_q   <= in_bus;
    a_col_q    <= a_col;
    b_row_q    <= b_row;
    en_q       <= en;
    clr_q      <= clr;
  end

  // Expected accumulator state one cycle after an accepted beat, computed from the SPEC
  // (full-width signed multiply-accumulate) rather than from the RTL expression.
  logic [511:0] acc_exp;
  always_comb
    for (int i = 0; i < 4; i++)
      for (int j = 0; j < 4; j++)
        acc_exp[(4*i+j)*32 +: 32] =
            $signed(acc_flat_q[(4*i+j)*32 +: 32])
          + $signed({{24{a_col_q[8*i+7]}}, a_col_q[8*i +: 8]})
          * $signed({{24{b_row_q[8*j+7]}}, b_row_q[8*j +: 8]});

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
  // A9: reset returns the WHOLE datapath + control to the power-on state — accumulators,
  // FSM state and drain row — from any point (mid-ACCEPT, mid-DRAIN; mac_reset_test).
  // Not disabled by reset itself. Checking acc alone would miss a reset that leaves the
  // FSM in DRAIN or the row counter mid-tile.
  a_reset_clear: assert property (@(posedge clk)
    !rst_n |=> acc_flat == '0 && state == 1'b0 && row == 2'd0);
  // A10: no phantom handshake during reset — the DUT must not advertise ready/valid
  a_reset_quiet: assert property (@(posedge clk)
    !rst_n |-> !in_ready && !out_valid);
  // A11: datapath. Every other assertion checks protocol or state; this one checks the
  // accumulated VALUE, so a wrap or sign-extension bug fails an assertion, not just the
  // scoreboard. (clr wins over en in the PE, so the clear case is excluded — that is A7.)
  a_acc_update: assert property (@(posedge clk) disable iff (!rst_n)
    en_q && !clr_q |-> acc_flat == acc_exp);
endmodule
