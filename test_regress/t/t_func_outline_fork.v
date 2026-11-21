// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Objects made and random numbers drawn in functions with a fork, with bodies
// larger than --output-split-cfuncs, get the same values as without
// splitting, see t_func_outline_fork_off

class Rand;
  rand int unsigned m_val;
endclass

module t;
  function automatic int mix15(int x);
    for (int k = 0; k < 15; k++) begin
      x = x * 3 + k;
      x ^= x >>> 2;
    end
    return x;
  endfunction

  // A fork in the middle
  function automatic Rand make(int x, output int unsigned rnd);
    /* verilator no_inline_task */
    std::process p;
    automatic int m = x;
    p = std::process::self();
    m = m * 3 + 0;
    m ^= m >>> 2;
    m = m * 3 + 1;
    m ^= m >>> 2;
    m = m * 3 + 2;
    m ^= m >>> 2;
    m = m * 3 + 3;
    m ^= m >>> 2;
    m = m * 3 + 4;
    m ^= m >>> 2;
    m = m * 3 + 5;
    m ^= m >>> 2;
    m = m * 3 + 6;
    m ^= m >>> 2;
    m = m * 3 + 7;
    m ^= m >>> 2;
    m = m * 3 + 8;
    m ^= m >>> 2;
    m = m * 3 + 9;
    m ^= m >>> 2;
    m = m * 3 + 10;
    m ^= m >>> 2;
    m = m * 3 + 11;
    m ^= m >>> 2;
    m = m * 3 + 12;
    m ^= m >>> 2;
    m = m * 3 + 13;
    m ^= m >>> 2;
    m = m * 3 + 14;
    m ^= m >>> 2;
    fork
      #1;
    join_none
    m = m * 3 + 0;
    m ^= m >>> 2;
    m = m * 3 + 1;
    m ^= m >>> 2;
    m = m * 3 + 2;
    m ^= m >>> 2;
    m = m * 3 + 3;
    m ^= m >>> 2;
    m = m * 3 + 4;
    m ^= m >>> 2;
    m = m * 3 + 5;
    m ^= m >>> 2;
    m = m * 3 + 6;
    m ^= m >>> 2;
    m = m * 3 + 7;
    m ^= m >>> 2;
    m = m * 3 + 8;
    m ^= m >>> 2;
    m = m * 3 + 9;
    m ^= m >>> 2;
    m = m * 3 + 10;
    m ^= m >>> 2;
    m = m * 3 + 11;
    m ^= m >>> 2;
    m = m * 3 + 12;
    m ^= m >>> 2;
    m = m * 3 + 13;
    m ^= m >>> 2;
    m = m * 3 + 14;
    m ^= m >>> 2;
    rnd = $urandom;
    make = new;
    make.m_val = m;
  endfunction

  // A fork before the statements that move
  function automatic Rand make2(int x, output int unsigned rnd);
    /* verilator no_inline_task */
    std::process p;
    automatic int m = x;
    p = std::process::self();
    fork
      #1;
    join_none
    m = m * 3 + 0;
    m ^= m >>> 2;
    m = m * 3 + 1;
    m ^= m >>> 2;
    m = m * 3 + 2;
    m ^= m >>> 2;
    m = m * 3 + 3;
    m ^= m >>> 2;
    m = m * 3 + 4;
    m ^= m >>> 2;
    m = m * 3 + 5;
    m ^= m >>> 2;
    m = m * 3 + 6;
    m ^= m >>> 2;
    m = m * 3 + 7;
    m ^= m >>> 2;
    m = m * 3 + 8;
    m ^= m >>> 2;
    m = m * 3 + 9;
    m ^= m >>> 2;
    m = m * 3 + 10;
    m ^= m >>> 2;
    m = m * 3 + 11;
    m ^= m >>> 2;
    m = m * 3 + 12;
    m ^= m >>> 2;
    m = m * 3 + 13;
    m ^= m >>> 2;
    m = m * 3 + 14;
    m ^= m >>> 2;
    m = m * 3 + 0;
    m ^= m >>> 2;
    m = m * 3 + 1;
    m ^= m >>> 2;
    m = m * 3 + 2;
    m ^= m >>> 2;
    m = m * 3 + 3;
    m ^= m >>> 2;
    m = m * 3 + 4;
    m ^= m >>> 2;
    m = m * 3 + 5;
    m ^= m >>> 2;
    m = m * 3 + 6;
    m ^= m >>> 2;
    m = m * 3 + 7;
    m ^= m >>> 2;
    m = m * 3 + 8;
    m ^= m >>> 2;
    m = m * 3 + 9;
    m ^= m >>> 2;
    m = m * 3 + 10;
    m ^= m >>> 2;
    m = m * 3 + 11;
    m ^= m >>> 2;
    m = m * 3 + 12;
    m ^= m >>> 2;
    m = m * 3 + 13;
    m ^= m >>> 2;
    m = m * 3 + 14;
    m ^= m >>> 2;
    rnd = $urandom;
    make2 = new;
    make2.m_val = m;
  endfunction

  initial begin
    Rand r1;
    Rand r2;
    int unsigned u1;
    int unsigned u2;
    int randomize_result;
    r1 = make(9, u1);
    `checkd(r1.m_val, mix15(mix15(9)));
    r2 = make2(9, u2);
    `checkd(r2.m_val, mix15(mix15(9)));
    randomize_result = r1.randomize();
    `checkd(randomize_result, 1);
    randomize_result = r2.randomize();
    `checkd(randomize_result, 1);
    $display("fork_new %0d %0d %0d %0d", r1.m_val, r2.m_val, u1, u2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
