// DESCRIPTION: Verilator: Verilog Test module
//
// The status results of randomize() and the rand_mode() query are truth
// values in logical operators and conditions, with no width warning.
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

class Cls extends Base;
  rand bit [6:0] v;
  function int self_check();
    if (!randomize()) return 0;
    if (!this.randomize() with {v != 7'h7f;}) return 0;
    return (randomize(v) && v.rand_mode()) ? 1 : 0;
  endfunction
endclass

module t;
  initial begin
    Cls c;
    Cls d;
    Base b;
    int x;
    int n;
    bit ok;
    c = new;
    b = c;
    if (!c.randomize()) `stop;
    if (!c.randomize() with {v != 0;}) `stop;
    if (!std::randomize(x)) `stop;
    if (!c.v.rand_mode()) `stop;
    if (!$cast(d, b)) `stop;
    ok = c.randomize() && $cast(d, b);
    `checkd(ok, 1'b1);
    ok = !c.randomize() || 1'b0;
    `checkd(ok, 1'b0);
    n = c.randomize() ? 7 : 3;
    `checkd(n, 7);
    n = c.self_check();
    `checkd(n, 1);
    c.v.rand_mode(0);
    n = c.v.rand_mode() ? 7 : 3;
    `checkd(n, 3);
    n = 0;
    while (c.randomize() && n < 3) ++n;
    `checkd(n, 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
