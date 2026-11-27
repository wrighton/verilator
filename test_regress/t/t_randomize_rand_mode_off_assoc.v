// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on


// An associative array with rand_mode() off is read as state (IEEE 1800-2023 18.8), a key it
// does not hold reading the default (7.8.6), also by a random key

class Held;
  rand bit [7:0] aa[int];
  rand int k;
  rand bit [7:0] v, w;
  constraint c {
    k inside {[0 : 9]};
    v == aa[k];
    w == aa[7];
  }
  function new();
    aa = '{2: 8'h22, 5: 8'h55, default: 8'h77};
  endfunction
endclass

// A random key into an array solved reads an element it holds, or the default
class Active;
  rand bit [7:0] aa[int];
  rand int idx;
  constraint c {
    idx inside {[0 : 5]};
    aa[idx] == 8'h9;
  }
  function new();
    aa = '{1: 8'h0, 2: 8'h0, 3: 8'h0};
  endfunction
endclass

// Keys narrower than a byte, wider than a word, and signed
class Widths;
  rand bit [7:0] a6[bit [5:0]];
  rand bit [7:0] a40[bit [39:0]];
  rand bit [7:0] al[longint];
  rand bit [5:0] k6;
  rand bit [39:0] k40;
  rand longint kl;
  constraint c {
    a6[k6] == 8'h16;
    a40[k40] == 8'h40;
    al[kl] == 8'h64;
  }
  function new();
    a6 = '{6'h3f: 8'h0, 6'h01: 8'h16, 6'h21: 8'h0};
    a40 = '{40'h12_0000_0005: 8'h40, 40'h00_0000_0005: 8'h0, 40'hff_ffff_ffff: 8'h0};
    al = '{-64'sd3: 8'h64, 64'sd3: 8'h0, 64'h1_0000_0000: 8'h0};
  endfunction
endclass

// Keys given only after new(), of more than 32 bits
class Late;
  rand bit [32:0] aa[longint];
  rand longint k;
  rand bit [32:0] v;
  constraint c {v == aa[k];}
endclass

// Many reads of a held array with many keys
class Many;
  rand bit [7:0] aa[int];
  rand int idx[64];
  rand bit [7:0] vals[64];
  constraint c {
    foreach (idx[i]) {
      idx[i] inside {[0 : 199]};
      vals[i] == aa[idx[i]];
    }
  }
  function new();
    for (int i = 0; i < 100; ++i) aa[2 * i] = 8'(i + 1);
  endfunction
endclass

module t;
  initial begin
    automatic Held o = new;
    automatic Many m = new;
    automatic Active a = new;
    automatic Widths wd = new;
    automatic bit [7:0] s6[bit [5:0]];
    automatic bit [7:0] sl[longint];
    automatic int ok;
    o.aa.rand_mode(0);
    repeat (10) begin
      ok = o.randomize();
      `checkh(ok, 1);
      `checkh(o.v, o.aa.exists(o.k) ? o.aa[o.k] : 8'h77);
      `checkh(o.w, 8'h77);
      `checkh(o.aa.size(), 2);
    end
    ok = o.randomize() with {v == 8'h55;};
    `checkh(ok, 1);
    `checkh(o.k, 5);
    ok = o.randomize() with {v == 8'h77;};
    `checkh(ok, 1);
    `checkh(o.aa.exists(o.k), 0);
    ok = o.randomize() with {v == 8'h33;};
    `checkh(ok, 0);
    // Solved again
    o.aa.rand_mode(1);
    ok = o.randomize() with {v == 8'h33;};
    `checkh(ok, 1);
    repeat (10) begin
      ok = a.randomize();
      `checkh(ok, 1);
      `checkh(a.aa.exists(a.idx), 1);
      `checkh(a.aa[a.idx], 8'h9);
      `checkh(a.aa.size(), 3);
    end
    // Keys changed since the last solve
    a.aa.delete(1);
    a.aa.delete(2);
    a.aa[4] = 8'h0;
    repeat (3) begin
      ok = a.randomize();
      `checkh(ok, 1);
      `checkh(a.idx == 3 || a.idx == 4, 1'b1);
      `checkh(a.aa[a.idx], 8'h9);
    end
    for (int frozen = 0; frozen < 2; ++frozen) begin
      if (frozen != 0) begin
        s6 = wd.a6;
        sl = wd.al;
        wd.a6.rand_mode(0);
        wd.a40.rand_mode(0);
        wd.al.rand_mode(0);
      end
      repeat (3) begin
        ok = wd.randomize();
        `checkh(ok, 1);
        `checkh(wd.a6.size() + wd.a40.size() + wd.al.size(), 9);
        `checkh(wd.a6.exists(wd.k6) && wd.a40.exists(wd.k40) && wd.al.exists(wd.kl), 1'b1);
        `checkh(wd.a6[wd.k6], 8'h16);
        `checkh(wd.a40[wd.k40], 8'h40);
        `checkh(wd.al[wd.kl], 8'h64);
        // Held as state
        if (frozen != 0) foreach (s6[k]) `checkh(wd.a6[k], s6[k]);
        if (frozen != 0) foreach (sl[k]) `checkh(wd.al[k], sl[k]);
      end
    end
    m.aa.rand_mode(0);
    ok = m.randomize();
    `checkh(ok, 1);
    foreach (m.idx[i]) `checkh(m.vals[i], m.aa.exists(m.idx[i]) ? m.aa[m.idx[i]] : 8'h0);
    // Keys changed since the last call with a randomize() with clause, and those of a copy,
    // whose original is gone
    begin
      automatic Held h = new;
      automatic Held hc;
      h.aa.rand_mode(0);
      ok = h.randomize() with {v == 8'h55;};
      `checkh(ok, 1);
      h.aa = '{3: 8'h33, default: 8'h77};
      ok = h.randomize() with {v == 8'h33;};
      `checkh(ok, 1);
      `checkh(h.k, 3);
      // A key replaced since the last call with a randomize() with clause
      h.aa.delete(3);
      h.aa[4] = 8'h44;
      ok = h.randomize() with {v == 8'h44;};
      `checkh(ok, 1);
      `checkh(h.k, 4);
      hc = new h;
      ok = hc.randomize() with {v == 8'h44;};
      `checkh(ok, 1);
      `checkh(hc.k, 4);
      hc.aa = '{8: 8'h88, default: 8'h77};
      h = null;
      repeat (2) begin
        ok = hc.randomize() with {v == 8'h88;};
        `checkh(ok, 1);
        `checkh(hc.k, 8);
      end
    end
    // A copy of an object of more keys than when made, changed by randomize() with clauses
    begin
      automatic Late l = new;
      automatic Late lc;
      l.aa.rand_mode(0);
      l.aa[5] = 33'h1_0000_0055;
      ok = l.randomize() with {v == 33'h1_0000_0055;};
      `checkh(ok, 1);
      `checkh(l.k, 5);
      l.aa.delete(5);
      l.aa[6] = 33'h66;
      l.aa[-9] = 33'h99;
      ok = l.randomize() with {v == 33'h99;};
      `checkh(ok, 1);
      `checkh(l.k, -9);
      lc = new l;
      ok = lc.randomize() with {v == 33'h66;};
      `checkh(ok, 1);
      `checkh(lc.k, 6);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
