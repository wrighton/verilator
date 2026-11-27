// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef int q_t[$];
typedef enum int {
  E0 = 0,
  E9 = 9
} e_t;

// The output arguments of a static task or function keep their values between calls
// (IEEE 1800-2023 13.3.2), those of an automatic one do not

module t;
  task static tk(output int o);
    o = o + 1;
  endtask
  // Static by the module's default lifetime, and a compound assignment
  task tk_default(output int o);
    o += 2;
  endtask
  // Not written by every call, so passes out the previous call's value when not
  task static tk_cond(input bit c, output int o);
    if (c) o = 5;
  endtask
  // Non-ANSI declaration
  task tk_old;
    output [7:0] o;
    begin
      o = o + 8'd3;
    end
  endtask
  function static int fn(output int o);
    o = o + 10;
    return 0;
  endfunction
  // Written by a system function or method
  task static tk_sscanf(input bit c, output int o);
    if (c) void'($sscanf("55", "%d", o));
  endtask
  task static tk_cast(input bit c, output e_t o);
    if (c) void'($cast(o, 9));
  endtask
  task static tk_queue(output q_t o);
    o.push_back(2);
  endtask
  // Always written first, so no different
  task static tk_written(input int v, output int o);
    o = v;
  endtask
  task automatic tk_auto(output int o);
    o = o + 1;
  endtask

  int a, b;
  logic [7:0] n;
  e_t e;
  q_t q;

  initial begin
    tk(a);
    `checkd(a, 1);
    tk(a);
    `checkd(a, 2);
    tk_default(a);
    `checkd(a, 2);
    tk_default(b);
    `checkd(b, 4);
    tk_cond(1, a);
    `checkd(a, 5);
    b = 99;
    tk_cond(0, b);
    `checkd(b, 5);
    tk_old(n);
    tk_old(n);
    `checkd(n, 6);
    void'(fn(a));
    `checkd(a, 10);
    void'(fn(a));
    `checkd(a, 20);
    tk_sscanf(1, a);
    `checkd(a, 55);
    b = 0;
    tk_sscanf(0, b);
    `checkd(b, 55);
    tk_cast(1, e);
    `checkd(e, E9);
    e = E0;
    tk_cast(0, e);
    `checkd(e, E9);
    tk_queue(q);
    tk_queue(q);
    `checkd(q.size(), 2);
    tk_written(3, a);
    `checkd(a, 3);
    tk_written(4, a);
    `checkd(a, 4);
    tk_auto(a);
    `checkd(a, 1);
    tk_auto(a);
    `checkd(a, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
