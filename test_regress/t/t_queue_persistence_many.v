// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Many elements passed by reference at once: creating, finding and releasing each reference
// takes constant time, so this runs in well under the time limit of the test
module t;
  localparam int N = 131072;
  int q[$];

  task automatic hold(ref int r);
    #10;
    r = -1;
  endtask

  initial begin
    for (int i = 0; i < 2 * N; ++i) q.push_back(i);
    for (int j = 0; j < N; ++j)
      fork
        automatic int k = j;
        hold(q[k]);
      join_none
    #1;
    // Operations on elements not passed by reference while the others are
    for (int i = 0; i < 1000000; ++i) begin
      q.push_back(i);
      void'(q.pop_back());
    end
    #20;
    `checkd(q.size(), 2 * N);
    for (int j = 0; j < N; ++j) if (q[j] != -1) `checkd(q[j], -1);
    `checkd(q[N], N);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
