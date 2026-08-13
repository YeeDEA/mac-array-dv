`timescale 1ns/1ps
// W3 integration TB: replays Python golden-model vectors (vectors.txt) against the array,
// with random input gaps and random drain backpressure. All checks are fatal-on-mismatch.
module mac_array_tb;
  logic clk = 0, rst_n = 0;
  logic in_valid = 0, in_last = 0, out_ready = 0;
  logic in_ready, out_valid, out_last;
  logic [1:0] out_row;
  logic [31:0] a_col = '0, b_row = '0;
  logic [127:0] c_row;

  mac_array_4x4 dut (.*);
  always #5 clk = ~clk;

  int fd, ncases, K;
  int A [4][64];
  int B [64][4];
  int C [4][4];

  task automatic send_beat(input logic [31:0] ac, input logic [31:0] br, input bit last);
    repeat ($urandom_range(0, 2)) begin
      in_valid <= 0;
      @(negedge clk);
    end
    while (!in_ready) @(negedge clk);
    in_valid <= 1; a_col <= ac; b_row <= br; in_last <= last;
    @(negedge clk);
    in_valid <= 0;
  endtask

  task automatic drain_and_check(input int case_id);
    for (int r = 0; r < 4; r++) begin
      while (!out_valid) @(negedge clk);
      repeat ($urandom_range(0, 2)) @(negedge clk); // hold out_ready low: backpressure
      if (out_row !== 2'(r))
        $fatal(1, "case %0d: out_row=%0d expected %0d", case_id, out_row, r);
      if (out_last !== (r == 3))
        $fatal(1, "case %0d: out_last wrong at row %0d", case_id, r);
      for (int j = 0; j < 4; j++) begin
        automatic int got = int'(c_row[32*j +: 32]);
        if (got !== C[r][j])
          $fatal(1, "case %0d: C[%0d][%0d] got %0d expected %0d", case_id, r, j, got, C[r][j]);
      end
      out_ready <= 1;
      @(negedge clk);
      out_ready <= 0;
    end
  endtask

  initial begin
    fd = $fopen("vectors.txt", "r");
    if (fd == 0) $fatal(1, "cannot open vectors.txt");
    void'($fscanf(fd, "%d", ncases));
    repeat (3) @(negedge clk);
    rst_n <= 1;
    @(negedge clk);

    for (int c = 0; c < ncases; c++) begin
      void'($fscanf(fd, "%d", K));
      for (int i = 0; i < 4; i++) for (int k = 0; k < K; k++) void'($fscanf(fd, "%d", A[i][k]));
      for (int k = 0; k < K; k++) for (int j = 0; j < 4; j++) void'($fscanf(fd, "%d", B[k][j]));
      for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) void'($fscanf(fd, "%d", C[i][j]));
      for (int k = 0; k < K; k++) begin
        automatic logic [31:0] ac, br;
        for (int i = 0; i < 4; i++) ac[8*i +: 8] = A[i][k][7:0];
        for (int j = 0; j < 4; j++) br[8*j +: 8] = B[k][j][7:0];
        send_beat(ac, br, k == K - 1);
      end
      drain_and_check(c);
    end

    $display("MAC_ARRAY TB PASS: %0d tiles checked", ncases);
    $finish;
  end

`ifdef DUMP
  initial begin
    $dumpfile("mac_array_tb.vcd");
    $dumpvars(0, mac_array_tb);
  end
`endif
endmodule
