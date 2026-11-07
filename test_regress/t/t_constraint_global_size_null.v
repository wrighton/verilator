// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// randomize(null) checks size constraints on arrays of rand member objects
// against their current sizes (IEEE 1800-2023 18.11.1)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Inner;
  rand int m_q[$];
  rand int m_d[];
endclass

class OuterBase;
  rand Inner m_in;
  rand int m_n;
  constraint c_size { m_in.m_q.size() == m_n; m_n inside {[1:4]}; m_in.m_d.size() == 2; }
  function new();
    m_in = new;
  endfunction
endclass

class Outer extends OuterBase;
  constraint c_d {
    foreach (m_in.m_q[i]) m_in.m_q[i] inside {[0:99]};
    foreach (m_in.m_d[i]) m_in.m_d[i] == i;
  }
endclass

// The element constraint in the member's own class, inherited by the outer class
class InnerOwn;
  rand int m_q[$];
  constraint c_elem { foreach (m_q[i]) m_q[i] inside {[0:99]}; }
endclass

class OuterOwnBase;
  rand InnerOwn m_in;
  rand int m_n;
  constraint c_size { m_in.m_q.size() == m_n; m_n inside {[1:4]}; }
  function new();
    m_in = new;
  endfunction
endclass

class OuterOwn extends OuterOwnBase;
endclass

module t;
  initial begin
    Outer o;
    OuterOwn oo;
    int ok;
    oo = new;
    repeat (5) begin
      ok = oo.randomize();
      `checkd(ok, 1);
      `checkd(oo.m_in.m_q.size(), oo.m_n);
      ok = oo.randomize(null);
      `checkd(ok, 1);
      oo.m_in.m_q[0] = 200;
      ok = oo.randomize(null);
      `checkd(ok, 0);
      oo.m_in.m_q[0] = 5;
      oo.m_in.m_q.push_back(1);
      ok = oo.randomize(null);
      `checkd(ok, 0);
    end
    o = new;
    // The sizes before any randomize()
    o.m_n = 2;
    o.m_in.m_q = '{1, 2};
    o.m_in.m_d = '{0, 1};
    ok = o.randomize(null);
    `checkd(ok, 1);
    repeat (5) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.m_in.m_q.size(), o.m_n);
      `checkd(o.m_in.m_d.size(), 2);
      ok = o.randomize(null);
      `checkd(ok, 1);
      o.m_in.m_q.push_back(1);
      ok = o.randomize(null);
      `checkd(ok, 0);
      void'(o.m_in.m_q.pop_back());
      o.m_in.m_q[0] = 200;
      ok = o.randomize(null);
      `checkd(ok, 0);
      o.m_in.m_q[0] = 5;
      o.m_in.m_d = '{0, 1, 2};
      ok = o.randomize(null);
      `checkd(ok, 0);
      o.m_in.m_d = '{0, 1};
      ok = o.randomize(null);
      `checkd(ok, 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
