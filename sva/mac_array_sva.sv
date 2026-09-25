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

  // Interface-derived tile tracker, independent of the ctrl FSM encoding: after the beat that
  // carries in_last is accepted, exactly four drain rows are owed before the tile is closed.
  // Built from handshakes only, so a refactor of ctrl.sv cannot make it agree by construction.
  wire in_hs   = in_valid && in_ready;
  wire out_hs  = out_valid && out_ready;
  wire tile_end = out_hs && out_last;      // drain of row 3 handshaked -> clear
  logic [2:0] rows_owed;
  always_ff @(posedge clk)
    if (!rst_n)                 rows_owed <= 3'd0;
    else if (in_hs && in_last)  rows_owed <= 3'd4;
    else if (out_hs && rows_owed != 0) rows_owed <= rows_owed - 3'd1;

  // A1 (rewritten, E6): while any of the four result rows is still owed, no new input beat
  // may be accepted, the output side must be offering a row, and out_last must mark exactly
  // the fourth row. The old A1 (out_valid |-> !in_ready) restated the 1-bit FSM decode and
  // could not fail; this one fails on a tile that drains too few rows (BUG2) or on input
  // accepted mid-drain.
  a_drain_blocks_in: assert property (@(posedge clk) disable iff (!rst_n)
    (rows_owed != 0) |-> !in_hs && out_valid && (out_last == (rows_owed == 3'd1)));
  // A12: and no row is ever offered that is not owed (added with the A1 rewrite)
  a_no_orphan_row: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid |-> rows_owed != 0);
  // A2: output data/row held while stalled
  a_out_stable: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid && !out_ready |=> out_valid && c_row == c_row_q && out_row == out_row_q);
  // A3: out_row increments per accepted drain beat
  a_row_inc: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid && out_ready && !out_last |=> out_row == 2'(out_row_q + 1));
  // A4: out_last exactly on row 3
  a_out_last_iff_row3: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid |-> (out_last == (out_row == 2'd3)));
  // A5 (rewritten, E6): no phantom accumulation. Antecedent is the INTERFACE (no input
  // handshake, no tile-end handshake), not the DUT's own en/clr — the old form trusted en,
  // so a bug that raised en without a handshake made it vacuous (BUG6).
  a_acc_stable_when_idle: assert property (@(posedge clk) disable iff (!rst_n)
    !in_hs && !tile_end |=> acc_flat == acc_flat_q);
  // A6 (rewritten, E6): no dropped beat. Every beat handshaked on the interface is
  // accumulated with the spec's arithmetic. The old A6 (en == in_valid && in_ready) was a
  // copy of the RTL assign; this checks the effect, not the wire (BUG7).
  a_en_iff_accept: assert property (@(posedge clk) disable iff (!rst_n)
    in_hs && !tile_end |=> acc_flat == acc_exp);
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
