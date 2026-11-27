// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A large array's model is read in time linear in its elements, and each hash spreading its
// solution samples a bounded number of its bits

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Big;
  rand int q[$];
  constraint c {
    q.size() == 4096;
    q[0] == 5;
    q[q.size() - 1] == 7;
  }
endclass

module t;
  initial begin
    automatic Big b = new;
    int ok;
    ok = b.randomize();
    `checkd(ok, 1);
    `checkd(b.q.size(), 4096);
    `checkd(b.q[0], 5);
    `checkd(b.q[4095], 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
