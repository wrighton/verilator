// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A vacuous success of a negated implication is a failure (IEEE 1800-2023 16.12.3)

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

  // Failures counted with blocking increments, as several attempts can fail on one tick
  int fail1 = 0, ref_fail1 = 0;
  int fail2 = 0, ref_fail2 = 0;
  int fail3 = 0, ref_fail3 = 0;
  int fail4 = 0, ref_fail4 = 0;
  int fail4p = 0;
  int fail5 = 0, ref_fail5 = 0;
  int fail6 = 0, ref_fail6 = 0;
  int fail7 = 0, ref_fail7 = 0;

  assert property (@(posedge clk) disable iff (cyc < 2) not (a |=> b))
  else ++fail1;

  assert property (@(posedge clk) disable iff (cyc < 2) not (a |-> b ##1 c))
  else ++fail2;

  // Vacuous success of the inner implication too
  assert property (@(posedge clk) disable iff (cyc < 2) not (a |-> (b |=> c)))
  else ++fail3;

  // Only the negated consequent's vacuous success fails
  assert property (@(posedge clk) disable iff (cyc < 2) a |-> not (b |=> c))
  else ++fail4;

  // The same with a pass action, which splits vacuous and nonvacuous passes
  assert property (@(posedge clk) disable iff (cyc < 2) a |-> not (b |=> c)) $write("");
  else ++fail4p;

  // Rejected threads of the operand are passes, not failures
  assert property (@(posedge clk) disable iff (cyc < 2) not (a ##1 b ##1 c))
  else ++fail5;

  // Alternatives ending on the same cycle
  assert property (@(posedge clk) disable iff (cyc < 2) not (a |-> ((b ##1 c) or (d ##1 c))))
  else ++fail6;

  // A followed-by has no vacuous success
  assert property (@(posedge clk) disable iff (cyc < 2) not (a #=# b))
  else ++fail7;

  always @(posedge clk) begin
    if (cyc >= 2) begin
      if (!a) ++ref_fail1;
      if (!a) ++ref_fail2;
      if (!a) ++ref_fail3;
      if (a && !b) ++ref_fail3;
      if (a && !b) ++ref_fail4;
      if (!a) ++ref_fail6;
    end
    if (cyc >= 3) begin
      if ($past(a) && b) ++ref_fail1;
      if ($past(a) && $past(b) && c) ++ref_fail2;
      if ($past(a) && $past(b) && c) ++ref_fail3;
      if ($past(a) && $past(b) && c) ++ref_fail4;
      if ($past(a) && ($past(b) || $past(d)) && c) ++ref_fail6;
      if ($past(a) && b) ++ref_fail7;
    end
    if (cyc >= 4 && $past(a, 2) && $past(b) && c) ++ref_fail5;
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
      `checkd(fail4p, ref_fail4);
      `checkd(fail5, ref_fail5);
      `checkd(fail6, ref_fail6);
      `checkd(fail7, ref_fail7);
      `checkd(ref_fail1, 76);
      `checkd(ref_fail2, 66);
      `checkd(ref_fail3, 86);
      `checkd(ref_fail4, 36);
      `checkd(ref_fail5, 10);
      `checkd(ref_fail6, 71);
      `checkd(ref_fail7, 26);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
