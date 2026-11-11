// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  // A class declared before a tristate net, in the same module
  class Cls;
  endclass

  int cyc = 0;
  wire en = cyc[0];
  wire tnet = en ? 1'b1 : 1'bz;
  logic isz;
  always_comb isz = (tnet === 1'bz);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkd(isz, !en);
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
