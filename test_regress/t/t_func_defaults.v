// DESCRIPTION: Verilator: Test for warning (not error) on improperly width'ed
// default function argument
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2015 Todd Strader
// SPDX-License-Identifier: CC0-1.0

parameter logic BAR = 1'b1;

function automatic logic calc_y;
  return 1'b1;
endfunction

function automatic logic [1:0] foo(input logic x = BAR, input logic y = calc_y());
  return x + y;
endfunction

class Foo;
  static int x;
  static function int get_x;
    return x;
  endfunction
endclass

function int mult2(int x = Foo::get_x());
  return 2 * x;
endfunction

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
  logic [1:0] foo_val;
  int b = 5;
  s_t st = '{x: 7};
  Cls c;

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
    foo_val = foo();
    if (foo_val != 2'b10) $stop;

    if (mult2(1) != 2) $stop;
    if (mult2() != 0) $stop;
    Foo::x = 30;
    if (mult2() != 60) $stop;

    if (f() != 5) $stop;
    b = 6;
    if (f() != 6) $stop;
    if (f(.b(1)) != 6) $stop;
    if (f_dot() != 7) $stop;
    if (f_arg(1) != 10) $stop;
    if (f_arg(2) != 20) $stop;
    if (pkg::pkg_f() != 50) $stop;
    c = new;
    if (c.f() != 3) $stop;
    c.m = 4;
    if (c.f() != 4) $stop;
    if (c.f_extern() != 4) $stop;

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
