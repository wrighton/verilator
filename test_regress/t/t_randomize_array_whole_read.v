// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A large one-dimensional array of the model is read whole, a small one by element; a whole
// value of another form is read by element instead, and nothing is written from a failed read

`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

class Whole;
  rand bit [7:0] d[];
  constraint c_d {
    d.size() == 100;
    foreach (d[i]) d[i] != 0;
  }
endclass

class Kinds;
  rand bit [7:0] f[100];
  rand bit [15:0] q[$];
  rand bit [7:0] s[];
  constraint c_k {
    q.size() == 80;
    s.size() == 10;
    foreach (f[i]) f[i] inside {[1 : 9]};
    foreach (q[i]) q[i] > 16'd10;
    foreach (s[i]) s[i] < 8'd5;
  }
endclass

module t;
  initial begin
    automatic Whole w = new;
    automatic Kinds k = new;
    automatic string want;
    automatic int ok;
    if (!$value$plusargs("want=%s", want)) want = "solved";
    w.d = new[100];
    foreach (w.d[i]) w.d[i] = 8'd1;
    ok = w.randomize();
    if (want == "failed") begin
      // Neither the whole read nor the one by element is written
      `checkd(ok, 0);
      foreach (w.d[i]) `checkd(w.d[i], 8'd1);
    end
    else if (want == "stores") begin
      `checkd(ok, 1);
      `checkd(w.d.size(), 100);
      foreach (w.d[i]) `checkd(w.d[i], i == 5 ? 8'h0b : i == 6 ? 8'd3 : 8'd7);
    end
    else begin
      `checkd(ok, 1);
      `checkd(w.d.size(), 100);
      foreach (w.d[i]) `checkd(w.d[i] != 0, 1'b1);
      // Read whole, though not written
      w.d.rand_mode(0);
      foreach (w.d[i]) w.d[i] = 8'd2;
      ok = w.randomize();
      `checkd(ok, 1);
      foreach (w.d[i]) `checkd(w.d[i], 8'd2);
      ok = k.randomize();
      `checkd(ok, 1);
      foreach (k.f[i]) `checkd(k.f[i] inside {[1 : 9]}, 1'b1);
      `checkd(k.q.size(), 80);
      foreach (k.q[i]) `checkd(k.q[i] > 16'd10, 1'b1);
      `checkd(k.s.size(), 10);
      foreach (k.s[i]) `checkd(k.s[i] < 8'd5, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
