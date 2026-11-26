// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A wait on a cycle of non-inlined calls, A -> Z -> Y -> B -> X -> A, made impure by X
module t;
  // verilog_format: off
  function automatic int A(int n); /*verilator no_inline_task*/
    return (n <= 0) ? 0 : Z(n - 1) + 1;
  endfunction
  function automatic int Y(int n); /*verilator no_inline_task*/
    return (n <= 0) ? 0 : B(n - 1) + 2;
  endfunction
  function automatic int B(int n); /*verilator no_inline_task*/
    return (n <= 0) ? 0 : X(n - 1) + 3;
  endfunction
  function automatic int X(int n); /*verilator no_inline_task*/
    int r;
    r = (n <= 0) ? 0 : A(n - 1);
    $display("X %0d", n);
    return r + 4;
  endfunction
  function automatic int Z(int n); /*verilator no_inline_task*/
    return (n <= 0) ? 0 : Y(n - 1) + 5;
  endfunction
  // verilog_format: on
  int sig = 0;
  int o = 0;
  int o2 = 0;
  initial o2 = A(6);
  initial begin
    wait (Z(sig) > 3);
    o = sig;
  end
  initial begin
    #1 sig = 2;
    #1;
    if (o != 2) $stop;
    if (o2 != 16) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
