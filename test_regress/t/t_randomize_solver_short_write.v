// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Cls;
  rand bit [30:0] v[4];
  constraint c_v {
    foreach (v[i]) {
      v[i] > 31'(i * 1000);
      v[i] < 31'(i * 1000 + 17);
    }
  }
endclass

module t;
  initial begin
    automatic Cls c = new;
    repeat (3) begin
      automatic int ok = c.randomize();
      `checkd(ok, 1);
      foreach (c.v[i]) begin
        `checkd(c.v[i] > 31'(i * 1000) && c.v[i] < 31'(i * 1000 + 17), 1);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
