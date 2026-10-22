// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Parameters in named blocks, tasks and functions can be set by defparam (IEEE 1800-2023 23.10.2)

module sub;
  parameter P = 10;
  int p, q, k, t;

  initial begin : blk
    parameter P = 1;
    p = P;
    begin : inner
      parameter Q = 5;
      q = Q;
    end
  end

  function automatic int f(input int x);
    parameter K = 1;
    return x * K;
  endfunction

  task automatic tsk(output int o);
    parameter T = 4;
    o = T;
  endtask

  initial begin
    k = f(3);
    tsk(t);
  end
endmodule

interface ifc;
  function automatic int g();
    parameter M = 1;
    return M;
  endfunction
endinterface

module wrap;
  sub u ();
  ifc i ();
endmodule

module t;
  sub u0 ();
  sub u1 ();
  sub u2 ();
  wrap w0 ();
  wrap w1 ();
  ifc i0 ();
  ifc i1 ();

  defparam u1.blk.P = 2;
  defparam u1.f.K = 3;
  defparam u1.tsk.T = 6;
  defparam u2.blk.inner.Q = 7;
  defparam u2.P = 20;
  defparam w1.u.blk.P = 8;
  defparam i1.g.M = 9;
  defparam w1.i.g.M = 11;

  initial begin
    #1;
    `checkd(u0.P, 10);
    `checkd(u0.p, 1);
    `checkd(u0.q, 5);
    `checkd(u0.k, 3);
    `checkd(u0.t, 4);
    `checkd(u1.P, 10);
    `checkd(u1.p, 2);
    `checkd(u1.q, 5);
    `checkd(u1.k, 9);
    `checkd(u1.t, 6);
    `checkd(u2.P, 20);
    `checkd(u2.p, 1);
    `checkd(u2.q, 7);
    `checkd(w0.u.p, 1);
    `checkd(w1.u.p, 8);
    `checkd(i0.g(), 1);
    `checkd(i1.g(), 9);
    `checkd(w0.i.g(), 1);
    `checkd(w1.i.g(), 11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
