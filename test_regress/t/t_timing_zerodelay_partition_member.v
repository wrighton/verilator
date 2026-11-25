// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A class member written by a clocked process is seen after a #0 in the same time step, also
// through another handle to the object

module t (
    input bit clk
);
  class payload;
    int value;
  endclass
  payload p = new;
  payload alias_p = p;
  always @(posedge clk) p.value = 17;
  initial
    for (int cyc = 1;; ++cyc) begin
      @(posedge clk);
      #0;
      `checkd(alias_p.value, 17);
      if (cyc == 3) begin
        $write("*-* All Finished *-*\n");
        $finish;
      end
    end
endmodule
