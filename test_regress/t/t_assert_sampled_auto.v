// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The sampled value of an automatic variable is its current value (IEEE 1800-2023 16.5.1)

class Cls;
  int same[3];
  task automatic check(int k);
    repeat (2) begin
      #10;
      if ($sampled(k) == k) same[k]++;
    end
  endtask
endclass

module t;
  Cls c = new;
  initial begin
    for (int i = 0; i < 3; i++) begin
      fork
        automatic int k = i;
        c.check(k);
      join_none
    end
    #30;
    for (int i = 0; i < 3; i++) `checkd(c.same[i], 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
