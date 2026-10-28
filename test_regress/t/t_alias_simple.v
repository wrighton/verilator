// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

module t (  /*AUTOARG*/
    // Inputs
    clk
);
  input clk;

  wire [31:0] a, b;
  wire [31:0] x, y;

  integer cyc = 0;

  alias a = b;
  assign a = cyc;

  alias x = y;
  assign x[15:0] = cyc[15:0];
  assign y[31:16] = cyc[31:16];

  sub s (cyc);

  wire [31:0] in_q1, in_q2;
  sub_in s_in (
      .d1(cyc),
      .d2(~cyc),
      .q1(in_q1),
      .q2(in_q2)
  );

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (a != cyc) $stop;
    if (b != cyc) $stop;

    if (x != cyc) $stop;
    if (y != cyc) $stop;

    if (s.a != cyc) $stop;
    if (s.b != cyc) $stop;

    if (in_q1 != cyc) $stop;
    if (in_q2 != ~cyc) $stop;
    $write("*-* All Finished *-*\n");
    $finish;

  end
endmodule

module sub (
    input integer cyc
);
  wire [31:0] a, b;
  assign a = cyc;
  alias a = b;
endmodule

module sub_in (
    input wire [31:0] d1,
    input wire [31:0] d2,
    output wire [31:0] q1,
    output wire [31:0] q2
);
  // Aliasing an input net is not a write to it (IEEE 1800-2023 10.11)
  wire [31:0] w1, w2;
  alias w1 = d1;
  alias d2 = w2;
  assign q1 = w1;
  assign q2 = w2;
endmodule
