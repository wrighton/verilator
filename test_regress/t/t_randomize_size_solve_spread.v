// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The solve of an array size first holds the elements of the old size; they are picked
// again with the new size, so the size solve spreads and reads back only the size

`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

class Sized;
  rand bit [7:0] d[];
  rand bit [31:0] n;
  constraint c_size {
    d.size() == n;
    n inside {[1 : 64]};
  }
  constraint c_val {foreach (d[i]) d[i] != 0;}
endclass

module t;
  initial begin
    automatic Sized s = new;
    automatic int seen[int];
    automatic int ok;
    s.srandom(1);
    repeat (30) begin
      ok = s.randomize();
      `checkd(ok, 1);
      `checkd(s.d.size(), int'(s.n));
      foreach (s.d[i]) `checkd(s.d[i] != 0, 1'b1);
      seen[s.d.size()] = 1;
    end
    // The sizes spread over their range: n is tied first to a value of its range, which the
    // size equal to it takes (about 24 of 64 values in 30 draws)
    `checkd(seen.num() >= 18, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
