// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Continuous assignments reading static variables of functions that are forced, or assigned by a
// procedural continuous assignment, later. Verilator evaluates these as if the function were
// inlined, so they follow the new values. The static variables are not operands of the
// assignments (IEEE 1800-2023 10.3.2), so other simulators may keep the old values.
module t;
  function automatic int f();
    static int s;
    s = $test$plusargs("choose_seven") ? 7 : 8;
    f = s;
  endfunction
  wire integer y;
  assign y = f();

  function automatic int g();
    static int s;
    s = $test$plusargs("choose_seven") ? 7 : 9;
    g = s;
  endfunction
  wire integer z;
  assign z = g();

  initial begin
    #1;
    `checkd(y, 8);
    `checkd(z, 9);
    force f.s = 42;
    // verilator lint_off IEEEMAYDEPRECATE
    assign g.s = 43;
    // verilator lint_on IEEEMAYDEPRECATE
    #1;
    `checkd(y, 42);
    `checkd(z, 43);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
