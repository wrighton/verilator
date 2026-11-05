// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc;
  reg [63:0] crc;

  // Derive signals from non-adjacent CRC bits to avoid LFSR shift correlation
  wire a = crc[0];
  wire b = crc[4];
  wire c = crc[8];
  wire d = crc[12];

  int count_fail1 = 0;
  int count_fail2 = 0;
  int count_fail3 = 0;
  int count_fail4 = 0;
  int count_pass5 = 0;
  int count_fail5 = 0;
  int count_pass6 = 0;
  int count_fail6 = 0;
  int count_fail7 = 0;
  int count_fail8 = 0;
  int count_fail9 = 0;
  int count_fail10 = 0;
  int count_fail11 = 0;
  int count_fail12;
  int count_fail13;

  // Test: a[=2] |-> b (overlapping implication, 2 non-consecutive occurrences)
  assert property (@(posedge clk) a [= 2] |-> b)
  else count_fail1 <= count_fail1 + 1;

  // Test: a[=1] |-> c (single occurrence, overlapping)
  assert property (@(posedge clk) a [= 1] |-> c)
  else count_fail2 <= count_fail2 + 1;

  // Test: a[=3] |=> d (3 occurrences, non-overlapping implication)
  assert property (@(posedge clk) a [= 3] |=> d)
  else count_fail3 <= count_fail3 + 1;

  // Test: standalone nonconsec rep (no implication)
  assert property (@(posedge clk) b [= 2])
  else count_fail4 <= count_fail4 + 1;

  // Test: nonconsec rep as consequent of an overlapping implication (#8612).
  // The antecedent holds every cycle, so no attempt is vacuous. Passes use a
  // blocking increment, as several attempts can pass on the same edge.
  assert property (@(posedge clk) cyc >= 0 |-> b [= 2]) count_pass5++;
  else count_fail5 <= count_fail5 + 1;

  // Test: nonconsec rep as consequent of a non-overlapping implication
  assert property (@(posedge clk) cyc >= 0 |=> d [= 2]) count_pass6++;
  else count_fail6 <= count_fail6 + 1;

  // Tests 7-12 have a cycle delay. Their action blocks run at each failing match, not once per
  // failing attempt, and the NBAs count the ticks with one.

  // Test 7: followed by a cycle delay, as antecedent
  assert property (@(posedge clk) a [= 2] ##1 b |-> c)
  else count_fail7 <= count_fail7 + 1;

  // Test 8: range followed by a cycle delay
  assert property (@(posedge clk) a [= 1: 2] ##1 b |-> c)
  else count_fail8 <= count_fail8 + 1;

  // Test 9: as test 7, through a sequence instance
  sequence s_nc_delay;
    a [= 2] ##1 b;
  endsequence
  assert property (@(posedge clk) s_nc_delay |-> c)
  else count_fail9 <= count_fail9 + 1;

  // Test 10: cycle delay in the consequent
  assert property (@(posedge clk) a [= 2] |=> c ##1 d)
  else count_fail10 <= count_fail10 + 1;

  // Test 11: as test 7, through a property declaration
  property p_nc_delay;
    @(posedge clk) a [= 2] ##1 b |-> c;
  endproperty
  assert property (p_nc_delay)
  else count_fail11 <= count_fail11 + 1;

  // Tests 12-13: as tests 7 and 1, under a default clocking in another module
  sub_default_clocking u_sub (
      .clk,
      .a,
      .b,
      .c,
      .count_fail_delay(count_fail12),
      .count_fail(count_fail13)
  );

  always @(posedge clk) begin
`ifdef TEST_VERBOSE
    $write("[%0t] cyc==%0d crc=%x a=%b b=%b c=%b d=%b\n", $time, cyc, crc, a, b, c, d);
`endif
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) begin
      crc <= 64'h5aef0c8d_d70a4497;
    end
    else if (cyc == 99) begin
      `checkh(crc, 64'hc77bb9b3784ea091);
      `checkd(count_fail1, 34);  // Other sims: 29, one other: 20
      `checkd(count_fail2, 27);  // Other sims: 32, one other: 25
      `checkd(count_fail3, 25);  // Other sims: 29, one other: 25
      `checkd(count_fail4, 0);
      `checkd(count_pass5, 91);
      `checkd(count_fail5, 0);
      `checkd(count_pass6, 96);
      `checkd(count_fail6, 0);
      `checkd(count_fail7, 19);  // Once per failing attempt: 15
      `checkd(count_fail8, 21);  // Once per failing attempt: 16
      `checkd(count_fail9, count_fail7);
      `checkd(count_fail10, 54);  // Once per failing attempt: 35
      `checkd(count_fail11, count_fail7);
      `checkd(count_fail12, count_fail7);
      `checkd(count_fail13, count_fail1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module sub_default_clocking (
    input clk,
    input a,
    input b,
    input c,
    output int count_fail_delay = 0,
    output int count_fail = 0
);
  default clocking @(posedge clk);
  endclocking
  assert property (a [= 2] ##1 b |-> c)
  else count_fail_delay <= count_fail_delay + 1;
  assert property (a [= 2] |-> b)
  else count_fail <= count_fail + 1;
endmodule
