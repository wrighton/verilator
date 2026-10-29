// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A default argument value is evaluated in the scope containing the subroutine
// (IEEE 1800-2023 13.5.3), even when an argument has the same name

package pkg;
  int b = 50;
  function automatic int pkg_f(int b = 2, int a = b);
    return a;
  endfunction
endpackage

typedef struct {int x;} s_t;

class Cls;
  int m = 3;
  function int f(int m = 9, int a = m);
    return a;
  endfunction
  extern function int f_extern(int m = 9, int a = m);
endclass

function int Cls::f_extern(int m = 9, int a = m);
  return a;
endfunction

module t;
  int b = 5;
  s_t st = '{x: 7};

  function automatic int f(int b = 2, int a = b);
    return a;
  endfunction
  function automatic int f_dot(s_t st = '{x: 1}, int a = st.x);
    return a;
  endfunction
  // Names only visible inside the subroutine still refer to its earlier arguments
  function automatic int f_arg(int sev, int verb = (sev == 1) ? 10 : 20);
    return verb;
  endfunction

  initial begin
    Cls c;
    c = new;
    `checkd(f(), 5);
    b = 6;
    `checkd(f(), 6);
    `checkd(f(.b(1)), 6);
    `checkd(f_dot(), 7);
    `checkd(f_arg(1), 10);
    `checkd(f_arg(2), 20);
    `checkd(pkg::pkg_f(), 50);
    c.m = 4;
    `checkd(c.f(), 4);
    `checkd(c.f_extern(), 4);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
