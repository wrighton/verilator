// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A cover property of an 'or' hits when an operand holds, and of a negated 'or' when every
// operand fails (IEEE 1800-2023 16.12.4, 16.14.3)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc;
  reg [63:0] crc;

  wire a = crc[0];
  wire c = crc[8];
  // Starts every second cycle; the operands exclude each other, so an attempt hits once
  wire s2 = (cyc[0] == 0);

  always @(negedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) crc <= 64'h5aef0c8d_d70a4497;
    if (cyc == 100) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Test: an operand holds
  int hit1 = 0, ref_hit1 = 0;
  cover property (@(posedge clk) disable iff (cyc < 2) (s2 && !a ##1 c) or (s2 && a)) ++hit1;
  always @(posedge clk) begin
    if (cyc >= 2 && s2 && a) ++ref_hit1;
    if (cyc >= 3 && $past(s2) && !$past(a) && c) ++ref_hit1;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(hit1, ref_hit1);
      `checkd(ref_hit1, 35);
    end
  end

  // Test: negated, every operand fails
  int hit2 = 0, ref_hit2 = 0;
  cover property (@(posedge clk) disable iff (cyc < 2) not ((!s2 || a) or (s2 && !a ##1 c)))
    ++hit2;
  always @(posedge clk) begin
    if (cyc >= 3 && $past(s2) && !$past(a) && !c) ++ref_hit2;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(hit2, ref_hit2);
      `checkd(ref_hit2, 14);
    end
  end
endmodule
