// DESCRIPTION: Verilator: Selective Kill aborts just the selected property attempt
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module site (
    input bit clk,
    input bit ready
);
  int passes = 0;
  int fails = 0;
  probe :
  assert property (@(posedge clk) (1'b1 until ready)) passes++;
  else fails++;
endmodule

module t;
  bit clk = 0;
  bit ready = 0;
  site selected (.clk, .ready);
  site sibling (.clk, .ready);

  initial begin
    #1 clk = 1;
    #1 $assertkill(0, selected.probe);
    #1 begin
      ready = 1;
      clk = 0;
    end
    #1 clk = 1;
    #1;
    `checkd(selected.passes, 0);
    `checkd(selected.fails, 0);
    `checkd(sibling.passes, 2);
    `checkd(sibling.fails, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
