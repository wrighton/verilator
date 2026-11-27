// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The pass action of an implication with a consequent of unbounded length runs once per attempt
// succeeding, also when several attempts waiting succeed on one tick (IEEE 1800-2023 16.14.1).
// The counts are checked against attempts enumerated from the sampled values.
module t;
  localparam int CYCLES = 120;

  bit clk = 0;
  always #5 clk = ~clk;

  int cyc = 0;
  bit [6:0] lfsr = 7'h5a;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    lfsr <= {lfsr[5:0], lfsr[6] ^ lfsr[5]};
  end
  wire a = lfsr[0];
  wire b = lfsr[2] & lfsr[3];
  wire c = lfsr[4] | lfsr[1];
  wire dis = (cyc % 23) == 17;

  int p[9], f[9];
  // Test: a wait of a delay without end
  assert property (@(posedge clk) a |-> ##[1:$] b) ++p[0];
  else ++f[0];
  assert property (@(posedge clk) a |-> ##[2:$] b) ++p[1];
  else ++f[1];
  // Test: a goto repetition
  assert property (@(posedge clk) a |-> b [-> 1]) ++p[2];
  else ++f[2];
  assert property (@(posedge clk) a |=> b [-> 2]) ++p[3];
  else ++f[3];
  // Test: an until, failing when c ends before b
  assert property (@(posedge clk) a |-> (c until b)) ++p[4];
  else ++f[4];
  // Test: an s_eventually, after a delay and after an antecedent of two ticks
  assert property (@(posedge clk) a |=> s_eventually b) ++p[7];
  else ++f[7];
  assert property (@(posedge clk) a ##1 c |-> s_eventually b) ++p[8];
  else ++f[8];
  // Test: disabled attempts end without a pass or fail
  assert property (@(posedge clk) disable iff (dis) a |-> ##[1:$] b) ++p[5];
  else ++f[5];
  // Test: killed attempts end too
  a_kill :
  assert property (@(posedge clk) a |-> b [-> 1]) ++p[6];
  else ++f[6];
  localparam int KILL = 50;
  initial begin
    repeat (KILL) @(posedge clk);
    @(negedge clk);
    $assertkill(0, a_kill);
    $asserton(0, a_kill);
  end

  // Test: many attempts waiting long pass together
  bit start = 0, done = 0;
  int long_p = 0;
  initial $assertvacuousoff(0, a_long);
  a_long :
  assert property (@(posedge clk) start |-> ##[1:$] done) ++long_p;
  else `stop;
  always @(negedge clk) begin
    start = cyc >= 2 && cyc < 102;
    done = cyc == 110;
  end

  bit ha[CYCLES], hb[CYCLES], hc[CYCLES], hd[CYCLES];
  always @(posedge clk) begin
    if (cyc < CYCLES) begin
      ha[cyc] = a;
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = dis;
    end
  end

  // The tick an attempt of a goto repetition b[->n] from tick s matches on, or CYCLES
  function automatic int gotoEnd(int s, int n);
    for (int t = s; t < CYCLES; ++t) begin
      if (hb[t]) begin
        --n;
        if (n == 0) return t;
      end
    end
    return CYCLES;
  endfunction

  initial begin
    repeat (CYCLES) @(posedge clk);
    #1;
    begin
      automatic int ep[9] = '{default: 0}, ef[9] = '{default: 0};
      for (int s = 0; s < CYCLES; ++s) begin
        automatic int r;
        automatic bit disabled = 0;
        if (!ha[s]) begin
          for (int i = 0; i < 9; ++i) ++ep[i];
          if (hd[s]) --ep[5];
          continue;
        end
        r = gotoEnd(s + 1, 1);
        if (r < CYCLES) ++ep[0];
        for (int t = s; t <= r && t < CYCLES; ++t) disabled |= hd[t];
        if (r < CYCLES && !disabled) ++ep[5];
        r = gotoEnd(s + 2, 1);
        if (r < CYCLES) ++ep[1];
        r = gotoEnd(s, 1);
        if (r < CYCLES) ++ep[2];
        if (r < CYCLES && !(s < KILL && r >= KILL)) ++ep[6];
        r = gotoEnd(s + 1, 2);
        if (r < CYCLES) ++ep[3];
        r = gotoEnd(s + 1, 1);
        if (r < CYCLES) ++ep[7];
        if (s + 1 < CYCLES && (!hc[s+1] || r < CYCLES)) ++ep[8];
        // c until b: passes on the first b, fails on a tick before without c
        for (int t = s; t < CYCLES; ++t) begin
          if (hb[t]) begin
            ++ep[4];
            break;
          end
          if (!hc[t]) begin
            ++ef[4];
            break;
          end
        end
      end
      for (int i = 0; i < 9; ++i) begin
        `checkd(p[i], ep[i]);
        `checkd(f[i], ef[i]);
      end
      `checkd(long_p, 100);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
