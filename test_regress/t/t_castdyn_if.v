// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Base;
endclass
class Derived extends Base;
endclass
class Other;
endclass

module t;
  typedef enum {
    ZERO,
    ONE
  } e_t;

  Base b;
  Derived d;
  Other o;
  e_t e;
  int i;
  int v;
  int r;

  initial begin
    d = new;
    // A $cast folded to a constant is a boolean condition without a width warning
    // verilator lint_off CASTCONST
    r = 0;
    if ($cast(b, d)) r = 1;
    `checkd(r, 1);
    if (b != d) `stop;
    if ($cast(b, o)) `stop;
    if ($cast(v, 5)) r = 2;
    `checkd(r, 2);
    `checkd(v, 5);
    // ... and a signed int
    if ($cast(v, 5) - 2 >= 0) `stop;
    // verilator lint_on CASTCONST
    // An enum $cast is checked at runtime
    i = $c32(1);
    if (!$cast(e, i)) `stop;
    `checkd(e, ONE);
    i = $c32(5);
    if ($cast(e, i)) `stop;
    `checkd(e, ONE);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
