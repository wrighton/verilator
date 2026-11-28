// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The size of a rand queue of class handles constrained only from below, through a random
// index, keeps the queue's size rather than growing it to any size

class Item;
  int nr;
endclass

class Holder;
  rand Item ps[$];
  rand int unsigned k;
  constraint c {k < ps.size();}
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic int ok;
    automatic Item p;
    for (int i = 0; i < 4; ++i) begin
      p = null;
      if (i % 2 != 0) p = new;
      h.ps.push_back(p);
    end
    repeat (10) begin
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.ps.size(), 4);
      `checkd(h.k < 4, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
