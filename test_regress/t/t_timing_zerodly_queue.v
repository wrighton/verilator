// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A queue written after a zero delay reaches the logic reading it before the next zero delay

module t;
  int q[$];
  int qy;
  always_comb qy = q.size();
  initial begin
    #1;
    #0 q.push_back(1);
    #0 `checkd(qy, 1);
    q.push_back(2);
    #0 `checkd(qy, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
