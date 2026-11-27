// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Callers of a cycle of non-inlined calls, A -> Z -> Y -> B -> X -> A, made impure by X: W
// enters it at Z, and W3 at A
module t (
    input clk,
    input int sig,
    output int o,
    output int o2,
    output int o3
);
  // verilog_format: off
  function automatic int W(int n); /*verilator no_inline_task*/
    return Z(n) + 1;
  endfunction
  function automatic int W3(int n); /*verilator no_inline_task*/
    return A(n) + 3;
  endfunction
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
  initial o2 = W(6);
  always @(posedge clk) o3 <= A(sig);
  always @(W3(sig)) o = sig;  // BAD: W3 is impure, through the cycle
endmodule
