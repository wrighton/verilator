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
  // The tick of each failure, as cycle counts
  int fails_first[$];
  int fails_late[$];
  int fails_fused[$];
  int fails_dropped[$];
  int fails_followed[$];
  int fails_negated[$];

  // The attempt of 2 fails on 5
  assert property (@(posedge clk) cyc == 2 |-> d[*1:$] ##1 c)
  else fails_first.push_back(tick);
  // The attempt of 7 matches on 10; that of 8 misses its second d on 10
  assert property (@(posedge clk) cyc == 7 |-> d[*1:$] ##1 c);
  assert property (@(posedge clk) cyc == 8 |=> d[*2:$] ##1 c)
  else fails_late.push_back(tick);
  // Fused: c on 10 needs d on 10 too
  assert property (@(posedge clk) cyc == 8 |-> d[*1:$] ##0 c)
  else fails_fused.push_back(tick);
  // d drops on 14 with c low
  assert property (@(posedge clk) cyc == 12 |-> d[*1:$] ##1 c)
  else fails_dropped.push_back(tick);
  // A sequence followed by another element, or negated, keeps its matches
  assert property (@(posedge clk) cyc == 7 |-> d[*1:$] ##1 c ##1 e)
  else fails_followed.push_back(tick);
  assert property (@(posedge clk) cyc == 7 |-> not (d[*1:$] ##1 c))
  else fails_negated.push_back(tick);

  always @(posedge clk) begin
    if (cyc == 16) begin
      `checkd(fails_first.size(), 1);
      `checkd(fails_first[0], 5);
      `checkd(fails_late.size(), 1);
      `checkd(fails_late[0], 10);
      `checkd(fails_fused.size(), 1);
      `checkd(fails_fused[0], 10);
      `checkd(fails_dropped.size(), 1);
      `checkd(fails_dropped[0], 14);
      `checkd(fails_followed.size(), 0);
      `checkd(fails_negated.size(), 1);
      `checkd(fails_negated[0], 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
