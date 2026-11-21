// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A property 'or' fails when every operand fails (IEEE 1800-2023 16.12.4)

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
  wire d = crc[16] & crc[20];
  wire e = crc[24] & crc[28];
  // Starts every second cycle, so each cycle has at most one failure
  wire s2 = (cyc[0] == 0);
  wire as2 = !s2 | a;
  // Starts every fourth cycle; a pending 'until' does not reach the next start
  wire s4 = (cyc[1:0] == 1);

  int fail1 = 0, ref_fail1 = 0;
  int fail2 = 0;
  int fail3 = 0, ref_fail3 = 0;
  int fail4 = 0, ref_fail4 = 0;
  int fail5 = 0;
  int fail6 = 0, ref_fail6 = 0;
  int fail7 = 0, ref_fail7 = 0;
  int fail8 = 0, ref_fail8 = 0;

  // Boolean or sequence at the end of the property
  assert property (@(posedge clk) disable iff (cyc < 2) (b ##1 c) or as2)
  else ++fail1;

  assert property (@(posedge clk) disable iff (cyc < 2) as2 or (b ##1 c))
  else ++fail2;

  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> ((b ##1 c) or a))
  else ++fail3;

  // Boolean disjunction inside a sequence
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a or b) ##1 c)
  else ++fail4;

  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a || b) ##1 c)
  else ++fail5;

  // Boolean or property
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a or (b |=> c)))
  else ++fail6;

  assert property (@(posedge clk) disable iff (cyc < 2) s4 |-> (d or (e until b)))
  else ++fail7;

  // A longer fixed delay
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a or (b ##3 c)))
  else ++fail8;

  bit until_pending = 0;

  always @(posedge clk) begin
    if (cyc >= 2) begin
      if (!as2 && !b) ++ref_fail1;
      if (s2 && !a && !b) ++ref_fail3;
      if (s2 && !a && !b) ++ref_fail4;
      if (s2 && !a && !b) ++ref_fail8;
      if (s4) `checkd(until_pending, 0);
      if (s4 && !d) until_pending = 1;
      if (until_pending && b) until_pending = 0;
      if (until_pending && !e) begin
        ++ref_fail7;
        until_pending = 0;
      end
    end
    if (cyc >= 3) begin
      if (!$past(as2) && $past(b) && !c) ++ref_fail1;
      if ($past(s2) && !$past(a) && $past(b) && !c) ++ref_fail3;
      if ($past(s2) && ($past(a) || $past(b)) && !c) ++ref_fail4;
      if ($past(s2) && !$past(a) && $past(b) && !c) ++ref_fail6;
    end
    if (cyc >= 5 && $past(s2, 3) && !$past(a, 3) && $past(b, 3) && !c) ++ref_fail8;
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
      `checkd(fail2, ref_fail1);
      `checkd(fail3, ref_fail3);
      `checkd(fail4, ref_fail4);
      `checkd(fail5, ref_fail4);
      `checkd(fail6, ref_fail6);
      `checkd(fail7, ref_fail7);
      `checkd(fail8, ref_fail8);
      `checkd(ref_fail7, 7);
      `checkd(ref_fail8, 17);
      `checkd(ref_fail1, 17);
      `checkd(ref_fail3, 17);
      `checkd(ref_fail4, 30);
      `checkd(ref_fail6, 7);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
