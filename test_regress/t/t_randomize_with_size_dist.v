// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A with-block sizing an array, so solved again after the sizes, with distributions whose ranges
// are read from state

class Item;
  rand bit [7:0] q[$];
  rand bit [3:0] len;
  rand bit [3:0] wid;
  bit [3:0] lo = 4'd3;
  bit [3:0] hi = 4'd6;
endclass

module t;
  initial begin
    automatic Item it = new;
    automatic int randomize_result;
    repeat (20) begin
      randomize_result = it.randomize() with {
        q.size() == 3;
        len dist {[lo : hi] := 1};
        wid dist {lo := 1, hi := 3};
      };
      `checkd(randomize_result, 1);
      `checkd(it.q.size(), 3);
      `checkd(it.len >= 4'd3 && it.len <= 4'd6, 1'b1);
      `checkd(it.wid == 4'd3 || it.wid == 4'd6, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
