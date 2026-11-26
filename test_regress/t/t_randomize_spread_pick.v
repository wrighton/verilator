// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A random index into elements none of which holds the value: the pin of every element
// conflicts once the index is free, so the element left to change is one of many
class Pick;
  rand int arr[];
  rand int i;
  constraint c {
    arr.size() == 32;
    i >= 0;
    i < arr.size();
    arr[i] == 77;
  }
endclass

module t;
  initial begin
    automatic Pick p = new;
    automatic int seen[int];
    automatic int ok;
    p.srandom(1);
    repeat (3) begin
      ok = p.randomize();
      `checkd(ok, 1);
      `checkd(p.arr[p.i], 77);
      seen[p.i] = 1;
    end
    // The element left to change is not always the same one
    `checkd(seen.num() >= 2, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
