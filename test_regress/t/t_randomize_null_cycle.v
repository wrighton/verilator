// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// randomize(null) on objects whose rand handles form a cycle checks each object once
// (IEEE 1800-2023 18.11.1)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef class A;

class B;
  rand int m_v;
  rand A m_a;
  int m_pre;
  int m_post;
  constraint c_b { m_v inside {[0:9]}; }
  function void pre_randomize();
    ++m_pre;
  endfunction
  function void post_randomize();
    ++m_post;
  endfunction
endclass

class A;
  rand int m_u;
  rand B m_b;
  constraint c_a { m_u inside {[0:9]}; }
endclass

module t;
  initial begin
    A a;
    B b;
    int ok;
    a = new;
    b = new;
    a.m_b = b;
    b.m_a = a;
    ok = a.randomize();
    `checkd(ok, 1);
    b.m_pre = 0;
    b.m_post = 0;
    ok = a.randomize(null);
    `checkd(ok, 1);
    `checkd(b.m_pre, 1);
    `checkd(b.m_post, 1);
    ok = b.randomize(null);
    `checkd(ok, 1);
    `checkd(b.m_pre, 2);
    `checkd(b.m_post, 2);
    b.m_v = 20;
    ok = a.randomize(null);
    `checkd(ok, 0);
    `checkd(b.m_post, 2);
    b.m_v = 3;
    a.m_u = 30;
    ok = b.randomize(null);
    `checkd(ok, 0);
    a.m_u = 3;
    ok = a.randomize(null);
    `checkd(ok, 1);
    ok = a.randomize();
    `checkd(ok, 1);
    ok = b.randomize();
    `checkd(ok, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
