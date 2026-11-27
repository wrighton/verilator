// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define PROPERTY_CHECK(msg) \
    $display("[%0t] stmt, %s", $time, msg); \
  else \
    $display("[%0t] else, %s", $time, msg); \
// verilog_format: on

module t;
  bit clk = 0;
  initial forever #1 clk = ~clk;

  localparam MAX = 1000;
  integer cyc = 0;
  integer passed = 0;
  integer passed_until = 0;

  assert property (@(negedge clk) s_eventually 1)
    ++passed;

  // 'until' after 's_eventually' in the same module (#8614)
  assert property (@(negedge clk) cyc > 0 until cyc > 0)
    ++passed_until;

  // An implication whose antecedent does not hold passes vacuously, running its pass action
  // (IEEE 1800-2023 16.12.7, 16.14.1)
  bit [30:0] lfsr = 31'h1234_5679;
  always @(negedge clk) lfsr <= {lfsr[29:0], lfsr[30] ^ lfsr[27]};
  wire a = lfsr[3] & lfsr[8];
  wire b = lfsr[5] & lfsr[11] & lfsr[17];
  int imp_n = 0;
  // Attempts still waiting for b at the end fail
  assert property (@(negedge clk) a |-> s_eventually b) ++imp_n;
  else;
  bit ah[MAX], bh[MAX];
  int ticks = 0;
  always @(negedge clk) begin
    ah[ticks] = a;
    bh[ticks] = b;
    ++ticks;
  end
  // Without vacuous passes, only those waiting for b run their pass action
  sub u_nonvac (.*);
  initial $assertvacuousoff(0, u_nonvac);
  // Passes of the attempts of ticks before n, vacuous ones too if vacuous is set
  function automatic int expPasses(int n, bit vacuous);
    int count = 0;
    for (int s = 0; s < n; ++s) begin
      if (!ah[s]) begin
        if (vacuous) ++count;
      end
      else begin
        for (int t = s; t < n; ++t) begin
          if (bh[t]) begin
            ++count;
            break;
          end
        end
      end
    end
    return count;
  endfunction

  always @(posedge clk) begin
    ++cyc;
    if (cyc == MAX) begin
      $display("%d", passed);
      if (passed != 999) $stop;
      if (passed_until != 999) $stop;  // Same as 'passed': each attempt passes on its first edge
      if (imp_n != expPasses(ticks, 1)) $stop;
      if (u_nonvac.n != expPasses(ticks, 0)) $stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module sub (
    input clk,
    input a,
    input b
);
  int n = 0;
  assert property (@(negedge clk) a |-> s_eventually b) ++n;
  else;
endmodule
