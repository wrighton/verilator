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

  // Stimulus on negedge so properties sample stable values
  always @(negedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) crc <= 64'h5aef0c8d_d70a4497;
    if (cyc == 100) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Test: boolean or sequence at the end of the property
  int fail1 = 0, fail2 = 0, ref_fail1 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) (b ##1 c) or as2)
  else ++fail1;
  assert property (@(posedge clk) disable iff (cyc < 2) as2 or (b ##1 c))
  else ++fail2;
  always @(posedge clk) begin
    if (cyc >= 2 && !as2 && !b) ++ref_fail1;
    if (cyc >= 3 && !$past(as2) && $past(b) && !c) ++ref_fail1;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail1, ref_fail1);
      `checkd(fail2, ref_fail1);
      `checkd(ref_fail1, 17);
    end
  end

  // Test: the same in an implication consequent
  int fail3 = 0, ref_fail3 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> ((b ##1 c) or a))
  else ++fail3;
  always @(posedge clk) begin
    if (cyc >= 2 && s2 && !a && !b) ++ref_fail3;
    if (cyc >= 3 && $past(s2) && !$past(a) && $past(b) && !c) ++ref_fail3;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail3, ref_fail3);
      `checkd(ref_fail3, 17);
    end
  end

  // Test: boolean disjunction inside a sequence
  int fail4 = 0, fail5 = 0, ref_fail4 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a or b) ##1 c)
  else ++fail4;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a || b) ##1 c)
  else ++fail5;
  always @(posedge clk) begin
    if (cyc >= 2 && s2 && !a && !b) ++ref_fail4;
    if (cyc >= 3 && $past(s2) && ($past(a) || $past(b)) && !c) ++ref_fail4;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail4, ref_fail4);
      `checkd(fail5, ref_fail4);
      `checkd(ref_fail4, 30);
    end
  end

  // Test: boolean or property
  int fail6 = 0, ref_fail6 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a or (b |=> c)))
  else ++fail6;
  always @(posedge clk) begin
    if (cyc >= 3 && $past(s2) && !$past(a) && $past(b) && !c) ++ref_fail6;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail6, ref_fail6);
      `checkd(ref_fail6, 7);
    end
  end

  // Test: boolean or a longer fixed delay
  int fail8 = 0, ref_fail8 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a or (b ##3 c)))
  else ++fail8;
  always @(posedge clk) begin
    if (cyc >= 2 && s2 && !a && !b) ++ref_fail8;
    if (cyc >= 5 && $past(s2, 3) && !$past(a, 3) && $past(b, 3) && !c) ++ref_fail8;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail8, ref_fail8);
      `checkd(ref_fail8, 17);
    end
  end

  // Test: boolean or an unbounded delay, which as a weak sequence fails only without a start
  // (IEEE 1800-2023 16.12.2)
  int fail9 = 0, ref_fail9 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a or (b ##[1:$] c)))
  else ++fail9;
  always @(posedge clk) begin
    if (cyc >= 2 && s2 && !a && !b) ++ref_fail9;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail9, ref_fail9);
      `checkd(ref_fail9, 10);
    end
  end

  // Test: chains of boolean disjunctions inside a sequence, nested either way
  int fail13 = 0, fail14 = 0, ref_fail13 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a || b || c) ##1 e)
  else ++fail13;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (a or (b or c)) ##1 e)
  else ++fail14;
  always @(posedge clk) begin
    if (cyc >= 2 && s2 && !a && !b && !c) ++ref_fail13;
    if (cyc >= 3 && $past(s2) && ($past(a) || $past(b) || $past(c)) && !e) ++ref_fail13;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail13, ref_fail13);
      `checkd(fail14, ref_fail13);
      `checkd(ref_fail13, 38);
    end
  end

  // Test: boolean or a bounded ranged delay before a multi-cycle sequence. An attempt starts
  // every fourth cycle and resolves within three.
  wire s4 = (cyc[1:0] == 1) && (cyc < 90);
  int fail15 = 0, ref_fail15 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) s4 |-> (a or (b ##[1:2] c ##1 d)))
  else ++fail15;
  always @(posedge clk) begin
    if (cyc >= 2 && s4 && !a && !b) ++ref_fail15;
    if (cyc >= 5 && $past(s4, 3) && !$past(a, 3) && $past(b, 3)
        && !(($past(c, 2) && $past(d, 1)) || ($past(c, 1) && d)))
      ++ref_fail15;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail15, ref_fail15);
      `checkd(ref_fail15, 10);
    end
  end

  // Test: an 'or' in an antecedent only matches, at a or at the end of !a ##1 c. The operands
  // exclude each other, so an attempt has one match, and it starts every second cycle.
  int fail10 = 0, ref_fail10 = 0;
  bit ant_pending = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) ((s2 && !a ##1 c) or (s2 && a)) |-> d)
  else ++fail10;
  always @(posedge clk) begin
    if (cyc >= 2) begin
      if (ant_pending && c && !d) ++ref_fail10;
      if (s2 && a && !d) ++ref_fail10;
      ant_pending = s2 && !a;
    end
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail10, ref_fail10);
      `checkd(ref_fail10, 24);
    end
  end

  // Test: a negated 'or' fails when an operand holds. The operands exclude each other, so an
  // attempt has one match.
  int fail11 = 0, ref_fail11 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not ((s2 && a) or (s2 && !a ##1 c)))
  else ++fail11;
  always @(posedge clk) begin
    if (cyc >= 2 && s2 && a) ++ref_fail11;
    if (cyc >= 3 && $past(s2) && !$past(a) && c) ++ref_fail11;
  end
  always @(negedge clk) begin
    if (cyc == 99) begin
      `checkd(fail11, ref_fail11);
      `checkd(ref_fail11, 35);
    end
  end

  // Test: a boolean disjunction inside the consequent of a followed-by
  int fail12 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) s2 |-> (1'b1 #-# ((a || b) ##1 c)))
  else ++fail12;
  always @(negedge clk) begin
    if (cyc == 99) `checkd(fail12, ref_fail4);
  end

  // Test: an 'or' that is an operand of a merging 'or' does not fail alone; here the outer
  // right operand matches after the inner one fails
  bit ngo = 0, na = 0, nb = 0, nc = 0, nd = 0, ne = 0;
  int nfail = 0;
  assert property (@(posedge clk) (ngo |-> (na or (nb ##1 nc))) or (nd ##1 ne))
  else ++nfail;
  always @(negedge clk) begin
    if (cyc == 4) {ngo, na, nb, nc, nd, ne} <= 6'b100010;
    if (cyc == 5) {ngo, na, nb, nc, nd, ne} <= 6'b001101;
    if (cyc == 6) {ngo, na, nb, nc, nd, ne} <= 6'b000000;
    if (cyc == 99) `checkd(nfail, 0);
  end

  // Test: an operand ending in a bounded ranged delay or an accept abort only matches, and
  // here every attempt succeeds
  bit rx = 1, ry = 0, rz = 0, rw = 0;
  int rfail = 0, rpass = 0;
  assert property (@(posedge clk) rx or (ry ##[1:2] rz)) ++rpass;
  else ++rfail;
  assert property (@(posedge clk) (ry ##[1:2] rz) or rx) ++rpass;
  else ++rfail;
  assert property (@(posedge clk) rx or (sync_accept_on (rw) (ry ##1 rz))) ++rpass;
  else ++rfail;
  always @(negedge clk) begin
    if (cyc == 4) {rx, ry, rz, rw} <= 4'b0100;
    if (cyc == 5) {rx, ry, rz, rw} <= 4'b1001;
    if (cyc == 6) {rx, ry, rz, rw} <= 4'b1010;
    if (cyc == 99) `checkd(rfail, 0);
  end

  // Test: the empty match of a[*0:1] ends the antecedent at eb, where ec holds
  bit eb = 0, ea = 0, ec = 0, ed = 0;
  int efail = 0;
  assert property (@(posedge clk) eb ##1 ea[*0:1] |-> (ec or ed))
  else ++efail;
  always @(negedge clk) begin
    if (cyc == 4) {eb, ea, ec, ed} <= 4'b1010;
    if (cyc == 5) {eb, ea, ec, ed} <= 4'b0000;
    if (cyc == 99) `checkd(efail, 0);
  end
endmodule
