// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Inline constraints on the elements of rand arrays of class handles keep the constraints of
// the elements' class (IEEE 1800-2023 18.5.8.1, 18.7)

typedef enum int {
  UNKNOWN,
  MEMORY,
  DEVICE
} kind_e;

class Cfg;
  rand int id;
  rand kind_e kind;
  rand bit [63:0] lo;
  constraint c_id {soft id == 0;}
  constraint c_kind {kind == MEMORY;}
endclass

class Mgr;
  int n = 3;
  rand Cfg cfg[];
  rand Cfg q[$];
  constraint c_size {
    cfg.size() == n;
    q.size() == n;
  }
  function void pre_randomize();
    if (cfg.size() == 0) begin
      cfg = new[n];
      foreach (cfg[i]) cfg[i] = new;
      repeat (n) begin
        Cfg c = new;
        q.push_back(c);
      end
    end
  endfunction
  function int randomizeSelf();
    return this.randomize() with {q[1].lo == 64'h5;};
  endfunction
endclass

module t;
  Mgr m;
  int ok;

  task automatic check();
    foreach (m.cfg[i]) begin
      `checkh(m.cfg[i].kind, MEMORY);
      `checkh(m.cfg[i].id, 0);
    end
    foreach (m.q[i]) begin
      `checkh(m.q[i].kind, MEMORY);
      `checkh(m.q[i].id, 0);
    end
  endtask

  initial begin
    m = new;
    repeat (5) begin
      // An element by index
      ok = m.randomize() with {cfg[0].lo == 64'h0;};
      `checkh(ok, 1);
      check();
      `checkh(m.cfg[0].lo, 64'h0);
      // Every element, by foreach
      ok = m.randomize() with {foreach (cfg[i]) cfg[i].lo == 64'h1;};
      `checkh(ok, 1);
      check();
      foreach (m.cfg[i]) `checkh(m.cfg[i].lo, 64'h1);
      // A queue element
      ok = m.randomize() with {q[2].lo == 64'h7;};
      `checkh(ok, 1);
      check();
      `checkh(m.q[2].lo, 64'h7);
      // Randomizing this
      ok = m.randomizeSelf();
      `checkh(ok, 1);
      check();
      `checkh(m.q[1].lo, 64'h5);
      // Without inline constraints
      ok = m.randomize();
      `checkh(ok, 1);
      check();
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
