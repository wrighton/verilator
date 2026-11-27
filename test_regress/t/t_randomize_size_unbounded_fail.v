// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A size read only in an implication antecedent, so solved again to keep it
class Ante;
  rand int q[$];
  rand int d[$];
  constraint c_ante {q.size() > 0 -> d.size() > 0;}
  constraint c_d {d.size() < 5;}
endclass

module t;
  initial begin
    automatic Ante ante = new;
    automatic int randomize_result;
    ante.q = '{7, 8};
    // With +died, the solver dies in the solve keeping the size: randomize() returns 0 and
    // changes nothing; the solver restarted, the next call keeps the size
    randomize_result = ante.randomize();
    `checkd(randomize_result, $test$plusargs("died") ? 0 : 1);
    `checkd(ante.q.size(), 2);
    randomize_result = ante.randomize();
    `checkd(randomize_result, 1);
    `checkd(ante.q.size(), 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
