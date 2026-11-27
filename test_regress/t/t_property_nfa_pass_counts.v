// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Passes of attempts completing in a cycle where another attempt fails still
// run the pass action (IEEE 1800-2023 16.14.1), checked against a reference model.

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

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Sampled values one cycle earlier
  bit a1, b1;
  always @(posedge clk) begin
    a1 <= a;
    b1 <= b;
  end

  // Vacuous and nonvacuous passes, without and with a fail action
  int pass_impl = 0, pass_impl_else = 0, ref_impl = 0;
  int fail_impl_else = 0, ref_fail_impl = 0;
  assert property (@(posedge clk) a |-> b ##1 c) pass_impl++;
  else;
  assert property (@(posedge clk) a |-> b ##1 c) pass_impl_else++;
  else fail_impl_else++;
  always @(posedge clk) ref_impl += int'(!a) + int'(a1 && b1 && c);
  // Per tick: an implication does not replay the fail action for another attempt failing too
  always @(posedge clk) ref_fail_impl += int'((a && !b) || (a1 && b1 && !c));

  // Followed-by has no vacuous pass
  int pass_followed = 0, ref_followed = 0;
  assert property (@(posedge clk) a #-# b ##1 c) pass_followed++;
  else;
  always @(posedge clk) ref_followed += int'(a1 && b1 && c);

  // Sequence property without a fail action
  int pass_seq = 0, ref_seq = 0;
  assert property (@(posedge clk) a ##1 b) pass_seq++;
  else;
  always @(posedge clk) ref_seq += int'(a1 && b);

  // Epochs of four ticks, ph 0 to 3, where an attempt fails on a tick another attempt passes
  wire [1:0] ph = cyc[1:0];
  wire odd_epoch = cyc[2];

  // Boolean antecedent: a nonvacuous pass at ph 1, a failure and a vacuous pass at ph 2, and a
  // vacuous pass at ph 3, each run per attempt
  wire e_a = ph == 0 || ph == 1;
  wire e_b = ph == 1;
  int pass_burst = 0, fail_burst = 0, pass_burst_auto = 0, fail_burst_auto = 0;
  assert property (@(posedge clk) e_a |-> ##1 e_b) pass_burst++;
  else fail_burst++;
  assert property (@(posedge clk) e_a |-> ##1 e_b) begin
    automatic int n = pass_burst_auto;
    pass_burst_auto = n + 1;
  end
  else begin
    automatic int n = fail_burst_auto;
    fail_burst_auto = n + 1;
  end

  // Sequence antecedent ending without a match: at ph 1 the attempt of ph 0 fails, or in odd
  // epochs passes, as that of ph 1 succeeds vacuously; at ph 3 and 0 the attempts of ph 2 and 3
  // succeed vacuously
  wire e_x = ph != 1;
  wire e_z = odd_epoch;
  int pass_end = 0, fail_end = 0;
  assert property (@(posedge clk) (e_x ##1 e_b) |-> e_z) pass_end++;
  else fail_end++;

  // A sequence with both actions: at ph 2 the attempt of ph 0 matches as those of ph 1 and 2
  // fail, and at ph 3 that of ph 3 fails. Replaying the fail action for the second failure at
  // ph 2 does not run the pass action again.
  wire e_p = ph == 0 || ph == 1;
  wire e_r = ph == 2;
  int pass_seq_both = 0, fail_seq_both = 0;
  assert property (@(posedge clk) e_p ##1 e_b ##1 e_r) pass_seq_both++;
  else fail_seq_both++;

  always @(negedge clk) begin
    if (cyc == 200) begin
      // 50 epochs
      `checkd(pass_burst, 150);
      `checkd(fail_burst, 50);
      `checkd(pass_burst_auto, 150);
      `checkd(fail_burst_auto, 50);
      // The attempt of tick 199 is pending
      `checkd(pass_end, 3 * 25 + 4 * 25 - 1);
      `checkd(fail_end, 25);
      `checkd(pass_impl, ref_impl);
      `checkd(pass_impl_else, ref_impl);
      `checkd(fail_impl_else, ref_fail_impl);
      `checkd(pass_followed, ref_followed);
      `checkd(pass_seq, ref_seq);
      `checkd(pass_seq_both, 50);
      `checkd(fail_seq_both, 150);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
