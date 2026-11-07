// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  logic rdy;
  p u_p (.rdy(rdy));

  initial begin
    #20;
    // No program has an initial procedure, so no implicit $finish (IEEE 1800-2023 24.7)
    `checkd($time, 20);
    `checkd(rdy, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule

// Neither a constant continuous assignment nor an empty generate loop is an initial procedure
program p (
    output logic rdy
);
  assign rdy = 1'b1;
  for (genvar i = 0; i < 0; ++i) begin : g_none
  end
endprogram
