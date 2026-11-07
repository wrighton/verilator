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

  wire [31:0] a, b, c, d;

  integer cyc = 0;
  assign a = cyc;

  sub s (
      .a(a),
      .b(b),
      .c(c),
      .d(d)
  );

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (a != cyc) $stop;
    if (b != cyc) $stop;

    $write("*-* All Finished *-*\n");
    $finish;

  end
endmodule

module sub (
    inout wire [31:0] a,
    inout wire [31:0] b,
    inout [31:0] c,  // Port kind omitted, so is a net (IEEE 1800-2023 23.2.2.3)
    inout [31:0] d
);
  alias a = b;
  alias c = d;
endmodule
