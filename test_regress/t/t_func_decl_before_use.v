// DESCRIPTION: Verilator: Verilog Test module
//
// A name in a task, function or block declaration refers to the outer declaration when the
// same name is declared later in that scope (IEEE 1800-2023 6.18).
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Cls #(
    int K = 5
);
  function bit [K-1:0] ones(input int K);
    return '1;
  endfunction
endclass

module t;
  localparam int K = 3;
  localparam int W = 9;

  // Return type and earlier input use the module K, not the later input K
  function automatic bit [K-1:0][7:0] widen;
    input bit [K-1:0][7:0] a;
    input bit [31:0] K;
    widen = a + 24'(K);
  endfunction

  function automatic logic [K*4-1:0] ansi(input logic [K*4-1:0] a, input int K);
    return a ^ 12'(K);
  endfunction

  task automatic tsk(input bit [K-1:0] a, output bit [K:0] o, input int K);
    o = 4'(a) + 4'(K);
  endtask

  // Local variables
  function automatic int local_init(int a);
    int w = K + a;
    int K = 7;
    begin : blk
      int v = W + a;
      int W = 11;
      return w * 1000 + K * 100 + v * 10 + W;
    end
  endfunction

  // A declaration earlier in the function is visible
  function automatic int earlier;
    localparam int W = 2;
    input bit [W-1:0] a;
    return $bits(a);
  endfunction

  // Positions in an included file are not compared with those of the including file
  function automatic int included;
    `include "t_func_decl_before_use.vh"
    input bit [W-1:0] a;
    return $bits(a);
  endfunction

  typedef logic [6:0] td_t;
  function automatic td_t ret_td(input td_t a);
    typedef logic [2:0] td_t;
    return a;
  endfunction

  // A forward typedef declares the name before its typedef
  typedef logic [7:0] fwd_t;
  function automatic int fwd_bits();
    typedef fwd_t;
    fwd_t v = 1;
    typedef int fwd_t;
    return $bits(v);
  endfunction

  // A typedef in a function
  function automatic int typedef_bits();
    typedef bit [K-1:0] k_t;
    localparam int K = 5;
    k_t v = '1;
    return $bits(v);
  endfunction

  initial begin : static_init
    static int w = W + 1;
    static int W = 4;
    `checkd(w, 10);
    `checkd(W, 4);
  end

  initial begin
    Cls c;
    bit [23:0] v;
    bit [11:0] u;
    bit [3:0] o;
    v = 24'h030201;
    u = 12'h5a5;
    c = new;
    `checkd($bits(widen(v, 1)), 24);
    `checkh(widen(v, 32'h10), 24'h030211);
    `checkd($bits(ansi(u, 1)), 12);
    `checkh(ansi(u, 2), 12'h5a7);
    tsk(u[2:0], o, 1);
    `checkh(o, 4'h6);
    `checkd(local_init(int'(u[3:0])), 8851);
    `checkd(earlier(2'b1), 2);
    `checkd(included(3'b1), 3);
    `checkd($bits(ret_td(7'h5)), 7);
    `checkd(fwd_bits(), 32);
    `checkd(typedef_bits(), 3);
    `checkd($bits(c.ones(1)), 5);
    `checkh(c.ones(1), 5'h1f);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
