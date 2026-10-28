// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// $bits of a dynamic array or queue is its current number of elements times the
// element size (IEEE 1800-2023 20.6.2)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  initial begin
    integer a[];
    `checkd($bits(a), 0);
    a = new[10];
    `checkd($bits(a), 10 * 32);
  end

  initial begin
    byte d[];
    logic [11:0] q[$];
    for (int i = 0; i < 5; ++i) begin
      d = new[i];
      `checkd($bits(d), i * 8);
      `checkd($bits(q), i * 12);
      q.push_back(12'(i));
    end
  end

  typedef enum logic [2:0] {E0, E1} e_t;
  typedef struct {
    logic [6:0] a;
    real r;
  } s_t;
  typedef logic [14:0] arr_t[$];

  initial begin
    e_t e[$];
    s_t s[];
    real r[$];
    logic [32:0] u[][3:1];
    arr_t t;
    e.push_back(E1);
    s = new[2];
    r = '{1.0, 2.0, 3.0};
    u = new[2];
    t = '{15'h1, 15'h2};
    `checkd($bits(e), 3);
    `checkd($bits(s), 2 * (7 + 64));
    `checkd($bits(r), 3 * 64);
    `checkd($bits(u), 2 * 3 * 33);
    `checkd($bits(t), 2 * 15);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
