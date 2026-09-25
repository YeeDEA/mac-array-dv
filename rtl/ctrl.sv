`timescale 1ns/1ps
// Tile control: ACCEPT (stream K beats, last flagged) -> DRAIN (rows 0..N-1) -> auto-clear -> ACCEPT.
module ctrl #(
  parameter int N   = 4      // N >= 2
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       in_valid,
  input  logic       in_last,
  output logic       in_ready,
  input  logic       out_ready,
  output logic       out_valid,
  output logic       out_last,
  output logic [$clog2(N)-1:0] out_row,
  output logic       en,
  output logic       clr
);
  localparam int RW = $clog2(N);
  typedef enum logic {S_ACCEPT, S_DRAIN} state_e;
  state_e state;
  logic [RW-1:0] row;

  wire accept_beat = in_valid && in_ready;
`ifdef BUG5
  wire drain_beat = out_valid;             // BUG5: drain advances without out_ready
`else
  wire drain_beat = out_valid && out_ready;
`endif

  // Reset-qualified: without rst_n here the FSM advertises in_ready throughout the
  // reset window, so a producer released one cycle early sees a phantom accept.
  assign in_ready  = rst_n && (state == S_ACCEPT);
  assign out_valid = rst_n && (state == S_DRAIN);
  assign out_row   = row;
`ifdef BUG2
  assign out_last  = (row == RW'(N - 2));  // BUG2: off-by-one, tile ends a row early
`else
  assign out_last  = (row == RW'(N - 1));
`endif
`ifdef BUG6
  assign en  = in_valid && rst_n;          // BUG6: accumulate on in_valid, ignoring in_ready
`elsif BUG7
  assign en  = accept_beat && !in_last;    // BUG7: last beat of every tile dropped
`else
  assign en  = accept_beat;
`endif
  assign clr = drain_beat && out_last;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= S_ACCEPT;
`ifndef BUG8
      row   <= '0;                         // BUG8 removes this: row survives a mid-drain reset
`endif
    end else begin
      unique case (state)
        S_ACCEPT: if (accept_beat && in_last) begin
                    state <= S_DRAIN;
                    row   <= '0;
                  end
        S_DRAIN:  if (drain_beat) begin
                    row <= row + 1'b1;
                    if (out_last) state <= S_ACCEPT;
                  end
      endcase
    end
  end
endmodule
