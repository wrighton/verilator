// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Size constraints on arrays of rand member objects reached through a null handle
// (IEEE 1800-2023 18.4) or a handle with rand_mode(0) (18.8)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Inner;
  rand int m_q[];
  rand int m_x;
  constraint c_inner { m_q.size() == 2; m_x < 10; }
endclass

// The constraints of Inner are copied into Outer (global constraints)
class Outer;
  rand Inner m_in;
  rand int m_n;
  constraint c_n { m_n inside {[1:5]}; }
endclass

// The outer class also constrains the size
class Sizer;
  rand Inner m_in;
  rand int m_n;
  constraint c_n { m_n inside {[1:5]}; m_n == m_in.m_q.size(); }
  function new();
    m_in = new;
    m_in.m_q = new[3];
  endfunction
endclass

module t;
  initial begin
    Outer o;
    Sizer s;
    int ok;

    // Null handle: its constraints and arrays are skipped
    o = new;
    ok = o.randomize();
    `checkd(ok, 1);
    ok = o.randomize() with { m_n < 3; };
    `checkd(ok, 1);
    ok = o.randomize(null);
    `checkd(ok, 1);
    o.m_in = new;
    o.m_in.m_q = new[5];
    ok = o.randomize(null);
    `checkd(ok, 0);
    ok = o.randomize();
    `checkd(ok, 1);
    `checkd(o.m_in.m_q.size(), 2);
    o.m_in = null;
    ok = o.randomize() with { m_n > 3; };
    `checkd(ok, 1);
    ok = o.randomize(null);
    `checkd(ok, 1);

    // Inactive handle: the array keeps its size, which the outer constraint uses
    s = new;
    s.m_in.rand_mode(0);
    ok = s.randomize();
    `checkd(ok, 1);
    `checkd(s.m_in.m_q.size(), 3);
    `checkd(s.m_n, 3);
    s.m_in.m_q = new[4];
    s.m_in.m_x = 50;
    ok = s.randomize() with { m_n > 0; };
    `checkd(ok, 1);
    `checkd(s.m_in.m_q.size(), 4);
    `checkd(s.m_in.m_x, 50);
    `checkd(s.m_n, 4);
    ok = s.randomize(null);
    `checkd(ok, 1);
    s.m_in.rand_mode(1);
    ok = s.randomize(null);
    `checkd(ok, 0);
    ok = s.randomize();
    `checkd(ok, 1);
    `checkd(s.m_in.m_q.size(), 2);
    `checkd(s.m_n, 2);
    s.m_in.rand_mode(0);
    s.m_in.m_q = new[1];
    ok = s.randomize();
    `checkd(ok, 1);
    `checkd(s.m_in.m_q.size(), 1);
    `checkd(s.m_n, 1);
    // Active handle, array with rand_mode(0): its size conflicts with c_inner
    s.m_in.rand_mode(1);
    s.m_in.m_q.rand_mode(0);
    s.m_in.m_q = new[5];
    ok = s.randomize();
    `checkd(ok, 0);
    `checkd(s.m_in.m_q.size(), 5);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
