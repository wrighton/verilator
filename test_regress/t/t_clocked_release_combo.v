// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// A force or release overrides, so is not another writer of an always_comb or
// always_ff variable (IEEE 1800-2023 9.2.2.2, 9.2.2.4, 10.6.2); no MULTIDRIVEN.
module t (  /*AUTOARG*/
    // Inputs
    clk
);
  input clk;

  logic [31:0] lhs1, lhs2, lhs3, rhs;
  logic cond = 0;

  always_comb lhs1 = rhs;
  assign lhs2 = rhs;

  always @(posedge clk) rhs = '1;

  always @(negedge clk) begin
    if (cond) begin
      force lhs1 = 'hdeadbeef;
      force lhs2 = 'hfeedface;
      force lhs3 = 'hcafef00d;
    end
    else begin
      release lhs1;
      release lhs2;
      release lhs3;
    end
  end

  always_ff @(posedge clk) lhs3 <= rhs;

  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 0) cond <= 1;
    if (cyc == 3) cond <= 0;
    if (cyc > 1 && cyc < 4) begin
      if (lhs1 != 'hdeadbeef) $stop;
      if (lhs2 != 'hfeedface) $stop;
      if (lhs3 != 'hcafef00d) $stop;
    end
    if (cyc > 4 && cyc < 8) begin
      if (lhs1 != '1) $stop;
      if (lhs2 != '1) $stop;
      if (lhs3 != '1) $stop;
    end
    if (cyc >= 8) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
