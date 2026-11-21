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
  int fail_ovl = 0, ref_fail_ovl = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not (a |=> b))
  else ++fail_ovl;
  always @(posedge clk) begin
    if (cyc >= 2 && !a) ++ref_fail_ovl;
    if (cyc >= 3 && $past(a) && b) ++ref_fail_ovl;
  end

  int fail_seq = 0, ref_fail_seq = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not (a |-> b ##1 c))
  else ++fail_seq;
  always @(posedge clk) begin
    if (cyc >= 2 && !a) ++ref_fail_seq;
    if (cyc >= 3 && $past(a) && $past(b) && c) ++ref_fail_seq;
  end

  // A boolean antecedent that is not a single term
  int fail_or = 0, ref_fail_or = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not ((a || b) |=> c))
  else ++fail_or;
  always @(posedge clk) begin
    if (cyc >= 2 && !(a || b)) ++ref_fail_or;
    if (cyc >= 3 && $past(a || b) && c) ++ref_fail_or;
  end

  // Vacuous success of the inner implication too
  int fail_inner = 0, ref_fail_inner = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not (a |-> (b |=> c)))
  else ++fail_inner;
  always @(posedge clk) begin
    if (cyc >= 2 && !a) ++ref_fail_inner;
    if (cyc >= 2 && a && !b) ++ref_fail_inner;
    if (cyc >= 3 && $past(a) && $past(b) && c) ++ref_fail_inner;
  end

  // Vacuous successes of two attempts on one tick, one of each implication
  int fail_inner2 = 0, ref_fail_inner2 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not (a |=> (b |=> c)))
  else ++fail_inner2;
  always @(posedge clk) begin
    if (cyc >= 2 && !a) ++ref_fail_inner2;
    if (cyc >= 3 && $past(a) && !b) ++ref_fail_inner2;
    if (cyc >= 4 && $past(a, 2) && $past(b) && c) ++ref_fail_inner2;
  end

  // Only the negated consequent's vacuous success fails
  int fail_cons = 0, ref_fail_cons = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) a |-> not (b |=> c))
  else ++fail_cons;
  always @(posedge clk) begin
    if (cyc >= 2 && a && !b) ++ref_fail_cons;
    if (cyc >= 3 && $past(a) && $past(b) && c) ++ref_fail_cons;
  end

  // The same with a pass action, which splits vacuous and nonvacuous passes
  int fail_cons_pass = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) a |-> not (b |=> c)) $write("");
  else ++fail_cons_pass;

  // Alternatives ending on the same cycle
  int fail_alt = 0, ref_fail_alt = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not (a |-> ((b ##1 c) or (d ##1 c))))
  else ++fail_alt;
  always @(posedge clk) begin
    if (cyc >= 2 && !a) ++ref_fail_alt;
    if (cyc >= 3 && $past(a) && ($past(b) || $past(d)) && c) ++ref_fail_alt;
  end

  // Without a fail action; passes are the failures of the implication
  int pass_true = 0, ref_pass_true = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not (1'b1 |=> b)) ++pass_true;
  else;
  always @(posedge clk) begin
    if (cyc >= 3 && !b) ++ref_pass_true;
  end

  // A followed-by has no vacuous success
  int fail_fby = 0, ref_fail_fby = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not (a #=# b))
  else ++fail_fby;
  always @(posedge clk) begin
    if (cyc >= 3 && $past(a) && b) ++ref_fail_fby;
  end

  // Stimulus on negedge so properties sample stable values
  always @(negedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) begin
      crc <= 64'h5aef0c8d_d70a4497;
    end
    else if (cyc == 99) begin
      `checkd(fail_ovl, ref_fail_ovl);
      `checkd(fail_seq, ref_fail_seq);
      `checkd(fail_or, ref_fail_or);
      `checkd(fail_inner, ref_fail_inner);
      `checkd(fail_inner2, ref_fail_inner2);
      `checkd(fail_cons, ref_fail_cons);
      `checkd(fail_cons_pass, ref_fail_cons);
      `checkd(fail_alt, ref_fail_alt);
      `checkd(fail_fby, ref_fail_fby);
      `checkd(pass_true, ref_pass_true);
      `checkd(ref_fail_ovl, 76);
      `checkd(ref_fail_seq, 66);
      `checkd(ref_fail_or, 64);
      `checkd(ref_fail_inner, 86);
      `checkd(ref_fail_inner2, 81);
      `checkd(ref_fail_cons, 36);
      `checkd(ref_fail_alt, 71);
      `checkd(ref_fail_fby, 26);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
