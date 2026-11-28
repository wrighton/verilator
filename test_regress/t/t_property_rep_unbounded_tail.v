// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin \
  $write("%%Error: %s:%0d: got=%0d exp=%0d (%s !== %s)\n", \
         `__FILE__, `__LINE__, (gotv), (expv), `"gotv`", `"expv`"); \
  `stop; \
end while (0)
// verilog_format: on

// An attempt of `d[*1:$] ##1 c` fails on the first tick on which neither c nor d holds after
// d held since its start, as no later match is possible (IEEE 1800-2023 16.9.2)
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  // The tick of the last clock, also where an action runs before the nonblocking assignment
  int tick = 0;
  always @(negedge clk) tick <= cyc;
  wire d = (cyc >= 2 && cyc <= 4) || (cyc >= 7 && cyc <= 9) || (cyc >= 12 && cyc <= 13);
  wire c = cyc == 10;
  wire e = cyc == 11;
  wire e1 = cyc == 1;
  // The tick of each failure, as cycle counts
  int fails_overlapping[$];
  int fails_late[$];
  int fails_fused[$];
  int fails_after_sequence[$];
  int fails_nested[$];
  int fails_goto[$];
  int fails_dropped[$];
  int fails_followed[$];
  int fails_negated[$];
  int fails_plain[$];

  // The attempts of 2, 3 and 4 fail together on 5
  assert property (@(posedge clk) (cyc == 2 || cyc == 3 || cyc == 4) |-> d[*1:$] ##1 c)
  else fails_overlapping.push_back(tick);
  // The attempt of 7 matches on 10; that of 8 misses its second d on 10
  assert property (@(posedge clk) cyc == 7 |-> d[*1:$] ##1 c);
  assert property (@(posedge clk) cyc == 8 |=> d[*2:$] ##1 c)
  else fails_late.push_back(tick);
  // Fused: c on 10 needs d on 10 too
  assert property (@(posedge clk) (cyc == 7 || cyc == 8) |-> d[*1:$] ##0 c)
  else fails_fused.push_back(tick);
  // After an antecedent of a fixed length, the attempts of 1, 2 and 3 fail together on 5
  assert property (@(posedge clk) (cyc >= 1 && cyc <= 3) ##1 1'b1 |=> d[*1:$] ##1 c)
  else fails_after_sequence.push_back(tick);
  // Nested in an implication, and after a goto repetition: each attempt fails on its own
  assert property (@(posedge clk) (cyc >= 1 && cyc <= 3) |-> (1'b1 ##1 1'b1 |=> d[*1:$] ##1 c))
  else fails_nested.push_back(tick);
  assert property (@(posedge clk) (cyc == 0 || cyc == 1) |-> (e1[->1] |=> d[*1:$] ##1 c))
  else fails_goto.push_back(tick);
  // d drops on 14 with c low
  assert property (@(posedge clk) cyc == 12 |-> d[*1:$] ##1 c)
  else fails_dropped.push_back(tick);
  // A sequence followed by another element, or negated, keeps its matches
  assert property (@(posedge clk) cyc == 7 |-> d[*1:$] ##1 c ##1 e)
  else fails_followed.push_back(tick);
  assert property (@(posedge clk) cyc == 7 |-> not (d[*1:$] ##1 c))
  else fails_negated.push_back(tick);
  // An attempt on each tick: those with d low fail at once
  assert property (@(posedge clk) d[*1:$] ##1 c)
  else fails_plain.push_back(tick);

  always @(posedge clk) begin
    if (cyc == 16) begin
      `checkd(fails_overlapping.size(), 3);
      foreach (fails_overlapping[i]) `checkd(fails_overlapping[i], 5);
      `checkd(fails_late.size(), 1);
      `checkd(fails_late[0], 10);
      `checkd(fails_fused.size(), 2);
      foreach (fails_fused[i]) `checkd(fails_fused[i], 10);
      `checkd(fails_after_sequence.size(), 3);
      foreach (fails_after_sequence[i]) `checkd(fails_after_sequence[i], 5);
      `checkd(fails_nested.size(), 3);
      foreach (fails_nested[i]) `checkd(fails_nested[i], 5);
      `checkd(fails_goto.size(), 2);
      foreach (fails_goto[i]) `checkd(fails_goto[i], 5);
      `checkd(fails_dropped.size(), 1);
      `checkd(fails_dropped[0], 14);
      `checkd(fails_followed.size(), 0);
      `checkd(fails_negated.size(), 1);
      `checkd(fails_negated[0], 10);
      // Ticks 0..15: d low on 0, 1, 5, 6, 10, 11, 14 and 15; 2..4 on 5, and 12..13 on 14
      `checkd(fails_plain.size(), 13);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
