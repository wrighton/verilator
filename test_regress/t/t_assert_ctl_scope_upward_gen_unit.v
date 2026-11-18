// DESCRIPTION: Verilator: Upward assertion control name found in the compilation unit
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

int unit_failures = 0;
task automatic gb();
  begin : inner
    check :
    assert (1'b0)
    else unit_failures++;
  end
endtask

module mid (
    input bit off
);
  initial if (off) $assertoff(0, gb.inner);
endmodule

// No gb is above the mid in qar, so its gb.inner is the compilation unit task's block
// (IEEE 1800-2023 23.8). The mid in par does not control: Verilator looks up gb in the
// compilation unit before par's generate block. Whether 23.8.1, for task and function names,
// makes that the expected binding for a name used as an assertion control scope is open.
module qar;
  mid m (1'b1);
endmodule

module par;
  int failures = 0;
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else failures++;
      end
    end
  end
  mid m (1'b0);
endmodule

module t;
  qar q ();
  par p ();
  initial begin
    #1;
    gb();
    #1;
    `checkd(unit_failures, 0);
    `checkd(p.failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
