// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Failures of separate attempts detected in the same cycle each run the
// action block (IEEE 1800-2023 16.14.1), checked against a reference model.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire a = crc[0];
  wire b = crc[5];
  wire c = crc[11];
  wire d = crc[9] | crc[13];  // Throughout guard, mostly true
  wire e = crc[17] & crc[23];  // Abort condition, mostly false
  bit dis = 0;  // Changes on negedge, so its current and sampled values agree

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end
  always @(negedge clk) dis <= crc[30:28] == 0;

  // Sampled history: [0] this cycle, [k] k cycles earlier
  bit [3:0] ah, bh, ch, dh, eh, sh;
  always_comb begin
    ah[0] = a;
    bh[0] = b;
    ch[0] = c;
    dh[0] = d;
    eh[0] = e;
    sh[0] = dis;
  end
  always @(posedge clk) begin
    ah[3:1] <= ah[2:0];
    bh[3:1] <= bh[2:0];
    ch[3:1] <= ch[2:0];
    dh[3:1] <= dh[2:0];
    eh[3:1] <= eh[2:0];
    sh[3:1] <= sh[2:0];
  end

  int fail_delay1 = 0, ref_delay1 = 0, ref_delay1_multi = 0;
  assert property (@(posedge clk) a ##1 b)
  else fail_delay1++;
  always @(posedge clk) begin
    automatic int n = int'(!ah[0]) + int'(ah[1] && !bh[0]);
    ref_delay1 += n;
    if (n > 1) ++ref_delay1_multi;
  end

  int fail_delay2 = 0, ref_delay2 = 0;
  assert property (@(posedge clk) a ##2 b)
  else fail_delay2++;
  always @(posedge clk) ref_delay2 += int'(!ah[0]) + int'(ah[2] && !bh[0]);

  int fail_chain = 0, ref_chain = 0;
  assert property (@(posedge clk) a ##1 b ##1 c)
  else fail_chain++;
  always @(posedge clk)
    ref_chain += int'(!ah[0]) + int'(ah[1] && !bh[0]) + int'(ah[2] && bh[1] && !ch[0]);

  int fail_range = 0, ref_range = 0;
  assert property (@(posedge clk) a ##[1:2] b)
  else fail_range++;
  always @(posedge clk) ref_range += int'(!ah[0]) + int'(ah[2] && !bh[1] && !bh[0]);

  int fail_rep = 0, ref_rep = 0;
  assert property (@(posedge clk) a ##1 b [* 2] ##1 c)
  else fail_rep++;
  always @(posedge clk)
    ref_rep += int'(!ah[0]) + int'(ah[1] && !bh[0]) + int'(ah[2] && bh[1] && !bh[0])
        + int'(ah[3] && bh[2] && bh[1] && !ch[0]);

  int fail_ovl = 0, ref_ovl = 0;
  assert property (@(posedge clk) a |-> b ##1 c)
  else fail_ovl++;
  always @(posedge clk) ref_ovl += int'(ah[0] && !bh[0]) + int'(ah[1] && bh[1] && !ch[0]);

  // With a pass action, which is split into vacuous and nonvacuous actions
  int pass_ovl_act = 0, fail_ovl_act = 0;
  assert property (@(posedge clk) a |-> b ##1 c) pass_ovl_act++;
  else fail_ovl_act++;

  int fail_nov = 0, ref_nov = 0;
  assert property (@(posedge clk) a |=> b ##2 c)
  else fail_nov++;
  always @(posedge clk) ref_nov += int'(ah[1] && !bh[0]) + int'(ah[3] && bh[2] && !ch[0]);

  // A guard drop and a missed step of the same thread fail it once
  int fail_through = 0, ref_through = 0;
  assert property (@(posedge clk) d throughout (a ##1 b ##1 c))
  else fail_through++;
  always @(posedge clk)
    ref_through += int'(!(dh[0] && ah[0])) + int'(dh[1] && ah[1] && !(dh[0] && bh[0]))
        + int'(dh[2] && ah[2] && dh[1] && bh[1] && !(dh[0] && ch[0]));

  // An abort and a failed final check of the same thread fail it once
  int fail_reject = 0, ref_reject = 0;
  assert property (@(posedge clk) a |-> reject_on (e) b ##1 c)
  else fail_reject++;
  always @(posedge clk)
    ref_reject += int'(ah[0] && (eh[0] || !bh[0]))
        + int'(ah[1] && !eh[1] && bh[1] && (eh[0] || !ch[0]));

  int fail_reject_through = 0, ref_reject_through = 0;
  assert property (@(posedge clk) a |-> reject_on (e) (d throughout b ##1 c))
  else fail_reject_through++;
  always @(posedge clk)
    ref_reject_through += int'(ah[0] && (eh[0] || !dh[0] || !bh[0]))
        + int'(ah[1] && !eh[1] && dh[1] && bh[1] && (eh[0] || !dh[0] || !ch[0]));

  // Rejected threads of a negated consequent are passes, not failures
  int fail_not = 0, ref_not = 0;
  assert property (@(posedge clk) a |-> not (b ##1 c))
  else fail_not++;
  always @(posedge clk) ref_not += int'(ah[1] && bh[1] && ch[0]);

  int fail_dis = 0, ref_dis = 0;
  assert property (@(posedge clk) disable iff (dis) a ##1 b ##1 c)
  else fail_dis++;
  always @(posedge clk)
    ref_dis += int'(!sh[0] && !ah[0]) + int'(sh[1:0] == 0 && ah[1] && !bh[0])
        + int'(sh[2:0] == 0 && ah[2] && bh[1] && !ch[0]);

  always @(negedge clk) begin
    if (cyc == 200) begin
      `checkd(fail_delay1, ref_delay1);
      `checkd(fail_delay2, ref_delay2);
      `checkd(fail_chain, ref_chain);
      `checkd(fail_range, ref_range);
      `checkd(fail_rep, ref_rep);
      `checkd(fail_ovl, ref_ovl);
      `checkd(fail_ovl_act, ref_ovl);
      `checkd(fail_nov, ref_nov);
      `checkd(fail_through, ref_through);
      `checkd(fail_reject, ref_reject);
      `checkd(fail_reject_through, ref_reject_through);
      `checkd(fail_not, ref_not);
      `checkd(fail_dis, ref_dis);
      // The stimulus produces cycles in which two attempts fail
      if (ref_delay1_multi == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
