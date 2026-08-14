`timescale 1ns/1ps
// UVM 1.2 environment for mac_array_4x4 — txn, sequences, agent (sequencer/driver/monitor),
// reference-model scoreboard, functional coverage subscriber, env, tests.
// Compile with: xvlog -sv -L uvm  (add -d NO_FCOV if covergroups fight the simulator)
package mac_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // 64 = the K the accumulator-width argument in docs/spec.md is stated for. The regression
  // must actually reach it, or the 32-bit accumulator claim is untested.
  localparam int KMAX = 64;

  // ---------------------------------------------------------------- stimulus item
  // One tile: K beats. Beat k, lane i: a = a_flat[4k+i], b = b_flat[4k+j].
  class mac_txn extends uvm_sequence_item;
    rand int unsigned k_len;
    rand byte a_flat [4*KMAX];
    rand byte b_flat [4*KMAX];

    // Weighted toward short tiles for runtime, but long tiles must appear — the
    // accumulator margin is only exercised near K = 64.
    constraint c_k { k_len inside {[1:KMAX]};
                     k_len dist {[1:8] :/ 50, [9:16] :/ 25, [17:32] :/ 15, [33:64] :/ 10}; }
    // corner-weighted operand distribution
    constraint c_a { foreach (a_flat[x]) a_flat[x] dist
      {-128 := 4, -1 := 2, 0 := 4, 1 := 2, 127 := 4, [-127:-2] :/ 10, [2:126] :/ 10}; }
    constraint c_b { foreach (b_flat[x]) b_flat[x] dist
      {-128 := 4, -1 := 2, 0 := 4, 1 := 2, 127 := 4, [-127:-2] :/ 10, [2:126] :/ 10}; }

    `uvm_object_utils(mac_txn)
    function new(string name = "mac_txn"); super.new(name); endfunction
  endclass

  // ---------------------------------------------------------------- observed tile
  class mac_obs extends uvm_object;
    logic [31:0]  a_beats [$];
    logic [31:0]  b_beats [$];
    logic [127:0] c_rows [4];

    `uvm_object_utils(mac_obs)
    function new(string name = "mac_obs"); super.new(name); endfunction
  endclass

  // ---------------------------------------------------------------- driver
  // Input and drain run as independent threads. That is what makes the next tile's first
  // beat show up while the previous tile is still draining — the only way in_valid && !in_ready
  // ever occurs, and therefore the only way assertion A8 is anything but a vacuous pass.
  class mac_driver extends uvm_driver #(mac_txn);
    virtual mac_if vif;
    int tiles_driven  = 0;
    int tiles_drained = 0;
    `uvm_component_utils(mac_driver)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual mac_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "mac_driver: no virtual interface")
    endfunction

    task run_phase(uvm_phase phase);
      vif.in_valid  <= 0;
      vif.in_last   <= 0;
      vif.out_ready <= 0;
      vif.a_col     <= '0;
      vif.b_row     <= '0;
      wait (vif.rst_n === 1'b1);
      @(negedge vif.clk);
      fork
        input_thread();
        drain_thread();
      join
    endtask

    task input_thread();
      mac_txn t;
      forever begin
        seq_item_port.get_next_item(t);
        drive_tile(t);
        tiles_driven++;
        seq_item_port.item_done();
      end
    endtask

    task drive_tile(mac_txn t);
      logic [31:0] ac, br;
      for (int k = 0; k < t.k_len; k++) begin
        for (int i = 0; i < 4; i++) ac[8*i +: 8] = t.a_flat[4*k+i];
        for (int j = 0; j < 4; j++) br[8*j +: 8] = t.b_flat[4*k+j];
        repeat ($urandom_range(0, 2)) begin      // random idle gaps
          vif.in_valid <= 0;
          @(negedge vif.clk);
        end
        // valid-first: assert the beat, then hold it stable until the DUT is ready.
        // in_ready read at a negedge is the value the upcoming posedge samples.
        vif.in_valid <= 1;
        vif.a_col    <= ac;
        vif.b_row    <= br;
        vif.in_last  <= (k == t.k_len - 1);
        while (!vif.in_ready) @(negedge vif.clk);  // stalled here => A8 antecedent fires
        @(negedge vif.clk);                        // let the accepting posedge pass
        vif.in_valid <= 0;
      end
    endtask

    task drain_thread();
      bit last;
      forever begin
        @(negedge vif.clk);
        if (vif.rst_n === 1'b1 && vif.out_valid) begin
          repeat ($urandom_range(0, 2)) @(negedge vif.clk);  // output backpressure
          last = vif.out_last;
          vif.out_ready <= 1;
          @(negedge vif.clk);
          vif.out_ready <= 0;
          if (last) tiles_drained++;
        end
      end
    endtask

    // Tests call this before dropping the objection: item_done() now fires when a tile's
    // input beats are in, which is one drain ahead of the tile actually being checked.
    task wait_all_drained();
      do @(negedge vif.clk);
      while (tiles_driven == 0 || tiles_drained < tiles_driven);
      repeat (2) @(negedge vif.clk);
    endtask
  endclass

  // ---------------------------------------------------------------- monitor
  class mac_monitor extends uvm_monitor;
    virtual mac_if vif;
    uvm_analysis_port #(mac_obs) ap;
    int fd;
    int n_in_stall  = 0;   // cycles of in_valid && !in_ready  (A8 antecedent)
    int n_out_stall = 0;   // cycles of out_valid && !out_ready (A2 antecedent)
    `uvm_component_utils(mac_monitor)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual mac_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "mac_monitor: no virtual interface")
      ap = new("ap", this);
      fd = $fopen("txn_dump.log", "w");
    endfunction

    task run_phase(uvm_phase phase);
      mac_obs cur = mac_obs::type_id::create("obs");
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n === 1'b1) begin
          if (vif.in_valid  && !vif.in_ready)  n_in_stall++;
          if (vif.out_valid && !vif.out_ready) n_out_stall++;
          if (vif.in_valid && vif.in_ready) begin
            cur.a_beats.push_back(vif.a_col);
            cur.b_beats.push_back(vif.b_row);
          end
          if (vif.out_valid && vif.out_ready) begin
            cur.c_rows[vif.out_row] = vif.c_row;
            if (vif.out_last) begin
              dump_tile(cur);
              ap.write(cur);
              cur = mac_obs::type_id::create("obs");
            end
          end
        end
      end
    endtask

    function void dump_tile(mac_obs o);
      if (fd == 0) return;
      $fwrite(fd, "TILE %0d\n", o.a_beats.size());
      foreach (o.a_beats[k]) $fwrite(fd, "AB %h %h\n", o.a_beats[k], o.b_beats[k]);
      for (int r = 0; r < 4; r++) begin
        $fwrite(fd, "C");
        for (int j = 0; j < 4; j++) $fwrite(fd, " %0d", int'(o.c_rows[r][32*j +: 32]));
        $fwrite(fd, "\n");
      end
    endfunction

    function void report_phase(uvm_phase phase);
      // Proof that the stimulus actually reached the stall scenarios. If n_in_stall is 0,
      // assertion A8 passed vacuously and the input-backpressure feature is unverified.
      if (n_in_stall == 0)
        `uvm_error("STIM", "in_valid && !in_ready never occurred — A8 is a vacuous pass")
      else
        `uvm_info("STIM", $sformatf("stall cycles observed: input=%0d output=%0d",
                  n_in_stall, n_out_stall), UVM_LOW)
    endfunction

    function void final_phase(uvm_phase phase);
      if (fd != 0) $fclose(fd);
    endfunction
  endclass

  // ---------------------------------------------------------------- scoreboard
  // Independent reference model: recompute C from monitored input beats (64-bit exact,
  // truncated to 32 to mirror the wrap-exact hardware accumulator).
  class mac_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(mac_obs, mac_scoreboard) aimp;
    int n_tiles = 0;
    int n_bad   = 0;
    `uvm_component_utils(mac_scoreboard)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      aimp = new("aimp", this);
    endfunction

    function void write(mac_obs o);
      longint acc [4][4];
      byte sa, sb;
      int exp32, got32;
      foreach (acc[i]) foreach (acc[i][j]) acc[i][j] = 0;
      foreach (o.a_beats[k]) begin
        for (int i = 0; i < 4; i++) begin
          sa = byte'(o.a_beats[k][8*i +: 8]);
          for (int j = 0; j < 4; j++) begin
            sb = byte'(o.b_beats[k][8*j +: 8]);
            acc[i][j] += sa * sb;
          end
        end
      end
      n_tiles++;
      for (int i = 0; i < 4; i++) begin
        for (int j = 0; j < 4; j++) begin
          automatic logic signed [31:0] raw = o.c_rows[i][32*j +: 32];
          // int'() would silently turn an undelivered (X) row into 0, which matches an
          // expected 0 — check for unknowns before the value compare.
          if ($isunknown(raw)) begin
            n_bad++;
            `uvm_error("SB", $sformatf("tile %0d C[%0d][%0d] is X — row never delivered",
                       n_tiles, i, j))
            continue;
          end
          exp32 = int'(acc[i][j]);
          got32 = int'(raw);
          if (got32 !== exp32) begin
            n_bad++;
            `uvm_error("SB", $sformatf("tile %0d C[%0d][%0d] got %0d expected %0d (K=%0d)",
                       n_tiles, i, j, got32, exp32, o.a_beats.size()))
          end
        end
      end
    endfunction

    function void report_phase(uvm_phase phase);
      if (n_bad == 0 && n_tiles > 0)
        `uvm_info("SB", $sformatf("SCOREBOARD PASS: %0d tiles, 0 mismatches", n_tiles), UVM_LOW)
      else
        `uvm_error("SB", $sformatf("SCOREBOARD FAIL: %0d tiles, %0d mismatches", n_tiles, n_bad))
    endfunction
  endclass

  // ---------------------------------------------------------------- functional coverage
  class mac_coverage extends uvm_subscriber #(mac_obs);
    int n_seen = 0;
`ifndef NO_FCOV
    byte cov_a, cov_b;
    int unsigned cov_k;

    covergroup cg_vals;
      option.per_instance = 1;
      cp_a: coverpoint cov_a {
        bins vmin  = {-128};
        bins vneg  = {[-127:-1]};
        bins vzero = {0};
        bins vpos  = {[1:126]};
        bins vmax  = {127};
      }
      cp_b: coverpoint cov_b {
        bins vmin  = {-128};
        bins vneg  = {[-127:-1]};
        bins vzero = {0};
        bins vpos  = {[1:126]};
        bins vmax  = {127};
      }
      x_ab: cross cp_a, cp_b;
    endgroup

    covergroup cg_tile;
      option.per_instance = 1;
      cp_k: coverpoint cov_k {
        bins k1     = {1};
        bins k_low  = {[2:4]};
        bins k_mid  = {[5:8]};
        bins k_high = {[9:16]};
        bins k_wide = {[17:63]};
        bins k_max  = {64};
        bins k_over = default;   // out-of-model K must not hide inside a legal bin
      }
    endgroup
`endif

    `uvm_component_utils(mac_coverage)
    function new(string name, uvm_component parent);
      super.new(name, parent);
`ifndef NO_FCOV
      cg_vals = new();
      cg_tile = new();
`endif
    endfunction

    function void write(mac_obs t);
      n_seen++;
`ifndef NO_FCOV
      cov_k = t.a_beats.size();
      cg_tile.sample();
      foreach (t.a_beats[k]) begin
        for (int i = 0; i < 4; i++) begin
          cov_a = byte'(t.a_beats[k][8*i +: 8]);
          cov_b = byte'(t.b_beats[k][8*i +: 8]);
          cg_vals.sample();
        end
      end
`endif
    endfunction

    function void report_phase(uvm_phase phase);
`ifndef NO_FCOV
      `uvm_info("COV", $sformatf("functional coverage: values=%0.1f%% tile=%0.1f%% (%0d tiles)",
                 cg_vals.get_inst_coverage(), cg_tile.get_inst_coverage(), n_seen), UVM_LOW)
`else
      `uvm_info("COV", $sformatf("SV covergroups compiled out (NO_FCOV); %0d tiles seen — Python coverage is authoritative", n_seen), UVM_LOW)
`endif
    endfunction
  endclass

  // ---------------------------------------------------------------- agent / env
  class mac_agent extends uvm_agent;
    uvm_sequencer #(mac_txn) sqr;
    mac_driver  drv;
    mac_monitor mon;
    `uvm_component_utils(mac_agent)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      sqr = uvm_sequencer#(mac_txn)::type_id::create("sqr", this);
      drv = mac_driver::type_id::create("drv", this);
      mon = mac_monitor::type_id::create("mon", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class mac_env extends uvm_env;
    mac_agent      agt;
    mac_scoreboard sb;
    mac_coverage   cov;
    `uvm_component_utils(mac_env)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      agt = mac_agent::type_id::create("agt", this);
      sb  = mac_scoreboard::type_id::create("sb", this);
      cov = mac_coverage::type_id::create("cov", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      agt.mon.ap.connect(sb.aimp);
      agt.mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  // ---------------------------------------------------------------- sequences
  class mac_random_seq extends uvm_sequence #(mac_txn);
    int unsigned n_tiles = 20;
    `uvm_object_utils(mac_random_seq)
    function new(string name = "mac_random_seq"); super.new(name); endfunction
    task body();
      repeat (n_tiles) begin
        req = mac_txn::type_id::create("req");
        start_item(req);
        if (!req.randomize()) `uvm_fatal("RAND", "randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  class mac_smoke_seq extends uvm_sequence #(mac_txn);
    `uvm_object_utils(mac_smoke_seq)
    function new(string name = "mac_smoke_seq"); super.new(name); endfunction
    // Two tiles, not one: the second tile's first beat is what stalls against the first
    // tile's drain, which is the only way the input-backpressure path is exercised.
    task body();
      repeat (2) begin
        req = mac_txn::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { k_len == 2; }) `uvm_fatal("RAND", "randomize failed")
        // deterministic small values on top of the random frame
        for (int x = 0; x < 8; x++) begin
          req.a_flat[x] = byte'(x + 1);        // 1..8
          req.b_flat[x] = byte'(-(x + 1));     // -1..-8
        end
        finish_item(req);
      end
    endtask
  endclass

  class mac_corner_seq extends uvm_sequence #(mac_txn);
    `uvm_object_utils(mac_corner_seq)
    function new(string name = "mac_corner_seq"); super.new(name); endfunction

    task send_const(input int unsigned k, input byte av, input byte bv);
      req = mac_txn::type_id::create("req");
      start_item(req);
      req.k_len = k;
      foreach (req.a_flat[x]) req.a_flat[x] = av;
      foreach (req.b_flat[x]) req.b_flat[x] = bv;
      finish_item(req);
    endtask

    task body();
      send_const(8,  8'sd0,    8'sd0);     // all-zero
      send_const(16, 8'sd127,  8'sd127);   // all-max
      send_const(16, -8'sd128, -8'sd128);  // all-min -> max positive products
      send_const(64, -8'sd128, 8'sd127);   // worst case: most-negative product x max K
      send_const(64, -8'sd128, -8'sd128);  // worst case: most-positive product x max K
      send_const(8,  8'sd42,   8'sd42);    // same-value
      send_const(1,  -8'sd128, -8'sd128);  // K=1 extreme
    endtask
  endclass

  // ---------------------------------------------------------------- tests
  class mac_base_test extends uvm_test;
    mac_env env;
    `uvm_component_utils(mac_base_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      env = mac_env::type_id::create("env", this);
      uvm_root::get().set_timeout(10ms, 0); // watchdog: a protocol-dead DUT hangs the drain loop
    endfunction
    virtual function uvm_sequence #(mac_txn) make_seq();
      mac_smoke_seq s = mac_smoke_seq::type_id::create("seq");
      return s;
    endfunction
    task run_phase(uvm_phase phase);
      uvm_sequence #(mac_txn) seq = make_seq();
      phase.raise_objection(this);
      seq.start(env.agt.sqr);
      env.agt.drv.wait_all_drained();  // item_done() runs a drain ahead of the check
      phase.drop_objection(this);
    endtask
  endclass

  class mac_smoke_test extends mac_base_test;
    `uvm_component_utils(mac_smoke_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass

  class mac_random_test extends mac_base_test;
    `uvm_component_utils(mac_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function uvm_sequence #(mac_txn) make_seq();
      mac_random_seq s = mac_random_seq::type_id::create("seq");
      if (!$value$plusargs("NTILES=%d", s.n_tiles)) s.n_tiles = 20;
      return s;
    endfunction
  endclass

  class mac_corner_test extends mac_base_test;
    `uvm_component_utils(mac_corner_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function uvm_sequence #(mac_txn) make_seq();
      mac_corner_seq s = mac_corner_seq::type_id::create("seq");
      return s;
    endfunction
  endclass
endpackage
