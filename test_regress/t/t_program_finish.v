// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

int ended = 0;

module t;

  // Free-running clock, the simulation only ends by the programs finishing
  logic clk = 0;
  always #5 clk = ~clk;

  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  p_delay #(.DELAY(10)) u_short ();
  p_delay #(.DELAY(37)) u_long ();
  p_zero u_zero ();
  ifc u_ifc ();

  final begin
    // IEEE 1800-2023 24.7: implicit $finish when the last program initial ends
    `checkd($time, 37);
    `checkd(cyc, 4);
    `checkd(ended, 5);
    $write("*-* All Finished *-*\n");
  end

endmodule

program p_delay #(
    parameter int DELAY = 1
);
  initial #DELAY ++ended;
  initial begin
    #(DELAY / 2);
    ++ended;
  end
endprogram

// Initial procedures outside programs do not delay the implicit $finish
interface ifc;
  initial #100 $stop;
endinterface

program p_zero;
  initial ++ended;
endprogram
