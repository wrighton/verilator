// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A property or sequence 'and' fails when either operand fails (IEEE 1800-2023 16.9.5, 16.12.5)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc;
  reg [63:0] crc;

  // Non-adjacent CRC bits to avoid LFSR shift correlation
  wire a = crc[0];
  wire b = crc[4];
  wire c = crc[8];
  wire d = crc[12];
  // Starts spaced by the property length, so each cycle has at most one failure
  wire s2 = (cyc[0] == 0);
  wire s4 = (cyc[1:0] == 0);

  int fail1 = 0, ref_fail1 = 0;
  int fail2 = 0, ref_fail2 = 0;
  int fail3 = 0, ref_fail3 = 0;
  int fail4 = 0, ref_fail4 = 0;
  int fail5 = 0, fail6 = 0, ref_fail5 = 0;

  // Fixed-length operands
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> ((a ##1 b) and (c ##1 d)))
  else ++fail1;

  assert property (@(posedge clk) disable iff (cyc < 2) s4 |-> ((a ##1 b) and (c ##2 d)))
  else ++fail2;

  // Boolean and property
  assert property (@(posedge clk) disable iff (cyc < 2) s4 |-> ((b ##[1:2] c) and a))
  else ++fail3;

  assert property (@(posedge clk) disable iff (cyc < 2) s4 |-> (a and (b |=> c)))
  else ++fail4;

  // Single-cycle operands
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a and (b |-> c)))
  else ++fail5;

  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> ((b |-> c) and a))
  else ++fail6;

  always @(posedge clk) begin
    if (cyc >= 2) begin
      if (s2 && !(a && c)) ++ref_fail1;
      if (s4 && !(a && c)) ++ref_fail2;
      if (s4 && !(a && b)) ++ref_fail3;
      if (s4 && !a) ++ref_fail4;
      if (s2 && !(a && (!b || c))) ++ref_fail5;
    end
    if (cyc >= 3) begin
      if ($past(s2) && $past(a && c) && !(b && d)) ++ref_fail1;
      if ($past(s4) && $past(a && c) && !b) ++ref_fail2;
      if ($past(s4) && $past(a && b) && !c) ++ref_fail4;
    end
    if (cyc >= 4) begin
      if ($past(s4, 2) && $past(a && c, 2) && $past(b) && !d) ++ref_fail2;
      if ($past(s4, 2) && $past(a && b, 2) && !$past(c) && !c) ++ref_fail3;
    end
  end

  // Stimulus on negedge so properties sample stable values
  always @(negedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) begin
      crc <= 64'h5aef0c8d_d70a4497;
    end
    else if (cyc == 99) begin
      `checkd(fail1, ref_fail1);
      `checkd(fail2, ref_fail2);
      `checkd(fail3, ref_fail3);
      `checkd(fail4, ref_fail4);
      `checkd(fail5, ref_fail5);
      `checkd(fail6, ref_fail5);
      `checkd(ref_fail5, 30);
      `checkd(ref_fail1, 45);
      `checkd(ref_fail2, 23);
      `checkd(ref_fail3, 16);
      `checkd(ref_fail4, 13);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
