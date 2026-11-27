// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Elements removed one after the other while passed by reference: each removal keeps the
// removed element for its reference, not the whole queue, so this runs in bounded memory,
// which the test driver checks
typedef struct {longint w[16];} big_t;  // 128 bytes

module t;
  localparam int NI = 20000;
  localparam int NB = 4000;
  int qi[$];
  big_t qb[$];

  task automatic hold_int(ref int r);
    #(4 * NI);
    r = -1;
  endtask
  task automatic hold_big(ref big_t r);
    #(4 * NI);
    r.w[0] = -1;
  endtask

  initial begin
    big_t b;
    for (int i = 0; i < NI; ++i) qi.push_back(i);
    for (int i = 0; i < NB; ++i) begin
      b.w[0] = longint'(i);
      qb.push_back(b);
    end
    for (int j = 0; j < NI; ++j) begin
      fork
        hold_int(qi[0]);
      join_none
      #1;
      `checkd(qi.pop_front(), j);
    end
    for (int j = 0; j < NB; ++j) begin
      fork
        hold_big(qb[0]);
      join_none
      #1;
      b = qb.pop_front();
      `checkd(b.w[0], longint'(j));
    end
    `checkd(qi.size(), 0);
    `checkd(qb.size(), 0);
    #(5 * NI);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
