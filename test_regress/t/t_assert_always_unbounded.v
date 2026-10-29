// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  logic a_high = 1'b1;
  logic a_low = 1'b0;
  logic a_drop = 1'b1;

  // Weak always [m:$] is a pure safety property: it has no end-of-trace
  // obligation, so it can only fail (else fires), once per failing tick.
  int high_fail_q[$];
  int low0_fail_q[$];
  int low2_fail_q[$];
  int drop_fail_q[$];

  // Constant-true input: never fails at any tick.
  assert property (@(posedge clk) always[2: $] a_high)
  else high_fail_q.push_back(cyc);

  // Constant-false input, m=0: fails at every observed tick.
  assert property (@(posedge clk) always[0: $] a_low)
  else low0_fail_q.push_back(cyc);

  // Constant-false input, m=2: fails at every tick once the window is live.
  assert property (@(posedge clk) always[2: $] a_low)
  else low2_fail_q.push_back(cyc);

  // a_drop is high then drops at cyc 5 and stays low: deterministic single
  // transition, so Verilator and others agree on the failing ticks exactly.
  assert property (@(posedge clk) always[2: $] a_drop)
  else drop_fail_q.push_back(cyc);

  // Under an implication: a_dip is sampled low at cyc 7 only, a_dip2 at cyc 7 and 8, and
  // a_dip3 at cyc 8 only
  logic a_dip = 1'b1;
  logic a_dip2 = 1'b1;
  logic a_dip3 = 1'b1;
  int impl0_fail_q[$];
  int impl0_now_fail_q[$];
  int impl0_after_fail_q[$];
  int impl0_twice_fail_q[$];
  int impl2_fail_q[$];
  assert property (@(posedge clk) cyc == 3 |-> always[0: $] a_dip)
  else impl0_fail_q.push_back(cyc);
  assert property (@(posedge clk) cyc == 7 |-> always[0: $] a_dip)
  else impl0_now_fail_q.push_back(cyc);
  assert property (@(posedge clk) cyc == 8 |-> always[0: $] a_dip)
  else impl0_after_fail_q.push_back(cyc);
  // The attempt ends at its first failure
  assert property (@(posedge clk) cyc == 3 |-> always[0: $] a_dip2)
  else impl0_twice_fail_q.push_back(cyc);
  assert property (@(posedge clk) cyc == 3 |-> always[2: $] a_dip3)
  else impl2_fail_q.push_back(cyc);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    a_dip <= cyc != 6;
    a_dip2 <= cyc != 6 && cyc != 7;
    a_dip3 <= cyc != 7;
    if (cyc >= 4) a_drop <= 1'b0;
    if (cyc == 19) begin
      // Counts pinned to Verilator (NFA per-cycle reject). The all-fail windows do not
      // include the end-of-simulation tick, as the $finish below takes effect before the
      // properties are sampled for this cycle; see the sva lessons "multi-cycle
      // end-of-simulation offset" note.
      `checkd(high_fail_q.size(), 0);
      `checkd(low0_fail_q.size(), 19);
      `checkd(low2_fail_q.size(), 17);
      `checkd(drop_fail_q[0], 5);  // All others: 6; first fail tick: a_drop sampled low from cyc 5
      `checkd(impl0_fail_q.size(), 1);
      `checkd(impl0_fail_q[0], 7);
      `checkd(impl0_now_fail_q.size(), 1);
      `checkd(impl0_now_fail_q[0], 7);
      `checkd(impl0_after_fail_q.size(), 0);
      `checkd(impl0_twice_fail_q.size(), 1);
      `checkd(impl0_twice_fail_q[0], 7);
      `checkd(impl2_fail_q.size(), 1);
      `checkd(impl2_fail_q[0], 8);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
