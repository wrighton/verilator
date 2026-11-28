// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A disable condition rising between clock events aborts the attempts of a property lowered per
// attempt that are in flight (IEEE 1800-2023 16.12), also where a term of it is a sampled value;
// an $assertkill ends the attempts in flight, but not one starting on the next clock event
// (IEEE 1800-2023 20.11).
module t;
  localparam int NCYC = 200;
  localparam int K = 61;  // The kill comes before this tick

  bit clk = 0;
  int cyc = 0;
  bit [30:0] lfsr = 31'h1234_5679;
  wire a = lfsr[3] | lfsr[7];
  wire b = lfsr[9] | lfsr[14];
  wire c = lfsr[17];
  wire d = lfsr[21] | lfsr[25];
  // Pulses of r between clock events, and q holding on some ticks
  bit r = 0;
  wire q = cyc % 29 == 7;

  int fails[4];
  int passes[4];
  // verilog_format: off
  assert property (@(posedge clk) disable iff (r) (a |-> ##2 b) and (c |-> ##1 d))
    ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) disable iff (r || $sampled(q)) (a |-> ##2 b) and (c |-> ##1 d))
    ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) disable iff (r && !$sampled(q)) (a |-> ##2 b) or (c |-> ##1 d))
    ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) (a |-> ##2 b) and (c |-> ##1 d)) ++passes[3];
  else ++fails[3];
  // verilog_format: on

  bit ha[NCYC + 4], hb[NCYC + 4], hc[NCYC + 4], hd[NCYC + 4], hq[NCYC + 4];
  bit pulse[NCYC + 4];  // A pulse of r came just before the tick
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hd[cyc] = d;
    hq[cyc] = q;
    cyc <= cyc + 1;
    lfsr <= {lfsr[29:0], lfsr[30] ^ lfsr[27]};
  end

  initial begin
    $assertvacuousoff;
    for (int i = 0; i < NCYC; ++i) begin
      #5 clk = 1;
      #3;
      if (i % 13 == 6) begin
        pulse[i+1] = 1;
        r = 1;
        #1 r = 0;
        #1;
      end
      else if (i + 1 == K) begin
        $assertkill;
        $asserton;
        #2;
      end
      else begin
        #2;
      end
      clk = 0;
    end
    #10 check();
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // Outcome of an attempt started on tick s: 0 none (disabled or killed), 1 pass, 2 fail
  function automatic int expect_attempt(int i, int s, output int tick);
    bit lhsOk = !ha[s] || hb[s+2];
    bit rhsOk = !hc[s] || hd[s+1];
    int lhsTick = ha[s] ? s + 2 : s;
    int rhsTick = hc[s] ? s + 1 : s;
    int outcome;
    if (i == 2) begin
      // 'or': passes on the first operand to pass, fails when both have failed
      if (lhsOk && (!rhsOk || lhsTick <= rhsTick)) tick = lhsTick;
      else if (rhsOk) tick = rhsTick;
      else tick = lhsTick > rhsTick ? lhsTick : rhsTick;
      outcome = lhsOk || rhsOk ? 1 : 2;
    end
    else begin
      if (!lhsOk && (rhsOk || lhsTick <= rhsTick)) tick = lhsTick;
      else if (!rhsOk) tick = rhsTick;
      else tick = lhsTick > rhsTick ? lhsTick : rhsTick;
      outcome = lhsOk && rhsOk ? 1 : 2;
    end
    // Killed: in flight across the kill
    if (s < K && tick >= K) return 0;
    // Disabled at the start, or by a pulse coming while it is in flight
    if ((i == 1 && hq[s]) || (i == 2 && 0)) return 0;
    if (i == 0 || i == 1) begin
      for (int k = s + 1; k <= tick; ++k) if (pulse[k] || (i == 1 && hq[k])) return 0;
    end
    if (i == 2) begin
      for (int k = s + 1; k <= tick; ++k) if (pulse[k] && !hq[k-1]) return 0;
    end
    return outcome;
  endfunction

  task automatic check();
    for (int i = 0; i < 4; ++i) begin
      int expPasses = 0, expFails = 0;
      for (int s = 0; s < NCYC; ++s) begin
        int tick;
        int outcome = expect_attempt(i, s, tick);
        if (tick > NCYC - 1) continue;
        if (outcome == 1 && tick > s) ++expPasses;  // vacuity is off: a pass on its start tick
        if (outcome == 1 && tick == s && (ha[s] || hc[s])) ++expPasses;
        if (outcome == 2) ++expFails;
      end
      `checkd(passes[i], expPasses);
      `checkd(fails[i], expFails);
    end
  endtask
endmodule
