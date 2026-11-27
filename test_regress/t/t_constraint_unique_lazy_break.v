// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A uniqueness group solved lazily, in a domain too small to spread the elements without equal
// ones, so each call is a lazy round and its fallback
class Tight;
  rand int qt[$];
  constraint c {
    unique {qt};
    foreach (qt[i]) qt[i] inside {[0 : 59]};
  }
  function new;
    repeat (40) qt.push_back(0);
  endfunction
endclass

module t;
  initial begin
    automatic Tight t = new;
    automatic int randomize_result;
    automatic int seen[int];
    repeat (16) begin
      randomize_result = t.randomize();
      `checkd(randomize_result, 1);
      seen.delete();
      foreach (t.qt[i]) begin
        `checkd(t.qt[i] inside {[0 : 59]}, 1);
        seen[t.qt[i]] = 1;
      end
      `checkd(seen.num(), 40);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
