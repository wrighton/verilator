// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 A.1.10 allows solve-before only as a constraint_block_item;
// inside a conditional it is ignored with a warning, leaving the other items.
// (Some simulators accept it there, as Verilator does inside foreach.)
class Cls;
  rand bit w;
  rand bit [3:0] a;
  rand bit b[2];
  rand bit [3:0] q[$];
  constraint c_if_foreach {
    if (w) {
      foreach (b[i]) {
        solve a before b[i];
        if (a[1]) {
          b[i] == 0;
        }
      }
    }
  }
  constraint c_if_else {
    if (w) {
      solve a before b;
      a > 2;
    } else {
      solve b before a;
    }
  }
  constraint c_implication {
    !w -> {
      solve a before b;
      a < 13;
    }
  }
  constraint c_if_foreach_only {
    if (w) {
      foreach (b[i]) {
        solve a before b[i];
      }
      foreach (b[i]) {
        unique {q};
      }
    }
  }
  constraint c_foreach_if {
    foreach (b[i]) {
      if (!w) {
        solve a before b[i];
      }
    }
  }
endclass

module t;
  initial begin
    automatic Cls obj = new;
    automatic int ok;
    automatic int randomize_result;
    repeat (20) begin
      randomize_result = obj.randomize();
      `checkd(randomize_result, 1);
      ok = int'((!obj.w || obj.a > 2) && (obj.w || obj.a < 13));
      `checkd(ok, 1);
      if (obj.w && obj.a[1]) begin
        `checkd(obj.b[0], 0);
        `checkd(obj.b[1], 0);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
