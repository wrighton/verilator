// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module sub (
    input logic a,
    input logic b,
    output logic q1,
    output logic q2
);
  // With the inputs tied to constants, these are only sensitive to constants
  always @(a) if (a) q1 <= 1'b1;
  always @(a or b) if (a && !b) q2 <= 1'b1;
endmodule

module t (
    input clk
);
  logic q1, q2;
  sub u_sub (
      .a(1'b1),
      .b(1'b0),
      .q1(q1),
      .q2(q2)
  );

  always @(posedge clk) begin
    `checkd(q1, 1'b1);
    `checkd(q2, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
