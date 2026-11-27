// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The pass actions of attempts passing on a tick when another attempt fails follow the pass
// control, not the fail control (IEEE 1800-2023 20.11)

module t (
    input clk
);
  localparam int EPOCHS = 6;  // Of four ticks, ph 0 to 3

  int cyc = 0;
  wire [1:0] ph = cyc[1:0];
  always @(posedge clk) cyc <= cyc + 1;

  // A sequence: at ph 2 the attempt of ph 0 matches as those of ph 1 and 2 fail, and at ph 3
  // that of ph 3 fails
  wire p = ph == 0 || ph == 1;
  wire q = ph == 1;
  wire r = ph == 2;
  int seq_pass = 0, seq_fail = 0;
  assert property (@(posedge clk) p ##1 q ##1 r) seq_pass++;
  else seq_fail++;

  // An implication: a nonvacuous pass at ph 1, a failure and a vacuous pass at ph 2, and a
  // vacuous pass at ph 3
  wire a = ph == 0 || ph == 1;
  wire b = ph == 1;
  int imp_pass = 0, imp_fail = 0;
  assert property (@(posedge clk) a |-> ##1 b) imp_pass++;
  else imp_fail++;

  // A sequence antecedent: at ph 2 the attempt of ph 0 fails as that of ph 1 ends without a match
  wire x = ph == 0;
  wire z = 0;
  int end_pass = 0, end_fail = 0;
  assert property (@(posedge clk) (x ##1 1) |-> ##1 z) end_pass++;
  else end_fail++;

  // A sequence passing on every tick, with no failing attempt
  wire always_true = ph <= 3;
  int clean_pass = 0, clean_fail = 0;
  assert property (@(posedge clk) always_true ##1 always_true ##1 always_true) clean_pass++;
  else clean_fail++;

  // An antecedent of several threads, whose attempts each pass two ticks later
  int multi_pass = 0;
  assert property (@(posedge clk) (always_true ##[1:2] always_true) |-> always_true) multi_pass++;

  initial $assertcontrol(7);  // PassOff

  // Between ticks, after the actions of the previous tick
  always @(negedge clk) begin
    if (cyc == 4 * EPOCHS) begin
      `checkd(seq_pass, 0);
      `checkd(seq_fail, 3 * EPOCHS);
      `checkd(imp_pass, 0);
      `checkd(imp_fail, EPOCHS);
      `checkd(end_pass, 0);
      `checkd(end_fail, EPOCHS);
      `checkd(clean_pass, 0);
      `checkd(clean_fail, 0);
      `checkd(multi_pass, 0);
      $assertcontrol(6);  // PassOn
      $assertcontrol(9);  // FailOff
    end
    if (cyc == 8 * EPOCHS) begin
      `checkd(seq_pass, EPOCHS);
      `checkd(seq_fail, 3 * EPOCHS);
      `checkd(imp_pass, 3 * EPOCHS);
      `checkd(imp_fail, EPOCHS);
      `checkd(end_pass, 3 * EPOCHS);
      `checkd(end_fail, EPOCHS);
      `checkd(clean_pass, 4 * EPOCHS);
      `checkd(clean_fail, 0);
      `checkd(multi_pass, 4 * EPOCHS);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
