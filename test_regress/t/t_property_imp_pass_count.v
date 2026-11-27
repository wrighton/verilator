// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The pass action of an implication runs once for each attempt succeeding (IEEE 1800-2023
// 16.12.7, 16.14.1), also when several attempts' consequents match on one tick, as for a ranged
// delay whose first match ends each attempt.
module t;
  bit clk = 0;
  always #5 clk = ~clk;
  bit [31:0] lfsr = 32'h1234_5678;
  always @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
  wire a = lfsr[3], b = lfsr[9], c = lfsr[17], d = lfsr[25];
  bit rst = 0;
  always @(posedge clk) rst <= lfsr[13] && lfsr[14] && lfsr[15];

  int n[10];
  assert property (@(posedge clk) a |-> ##[1:2] b) n[0]++;
  else;
  assert property (@(posedge clk) a |=> ##[1:2] b) n[1]++;
  else;
  assert property (@(posedge clk) a |-> b ##[1:3] c) n[2]++;
  else;
  assert property (@(posedge clk) a |-> ##[0:2] b) n[3]++;
  else;
  assert property (@(posedge clk) a |-> ##1 b ##[1:2] c) n[4]++;
  else;
  // An antecedent of several ticks, its vacuous successes counted
  assert property (@(posedge clk) (a ##1 d) |-> ##[1:2] c) n[5]++;
  else;
  assert property (@(posedge clk) a #-# ##[1:2] b) n[6]++;
  else;
  assert property (@(posedge clk) disable iff (rst) a |-> ##[1:2] b) n[7]++;
  else;
  // A consequent of one thread per attempt
  assert property (@(posedge clk) a |-> b ##1 c) n[8]++;
  else;
  // Of several threads, each still passing once on a tick
  assert property (@(posedge clk) a |-> (b ##1 c or d)) n[9]++;
  else;
  int m[5];
  assert property (@(posedge clk) a |-> c [*1:2]) m[0]++;
  else;
  assert property (@(posedge clk) a |-> b [*1:2] ##[1:2] d) m[1]++;
  else;
  assert property (@(posedge clk) a |-> ##[1:2] (b ##1 c)) m[2]++;
  else;
  assert property (@(posedge clk) a |-> ##[1:$] b) m[3]++;
  else;
  assert property (@(posedge clk) a |-> b [->1]) m[4]++;
  else;

  // Oracle: the tick each attempt succeeds on, if it does
  bit ah[$], bh[$], ch[$], dh[$], rh[$];
  always @(posedge clk) begin
    ah.push_back(a);
    bh.push_back(b);
    ch.push_back(c);
    dh.push_back(d);
    rh.push_back(rst);
  end
  // The first tick of [lo:hi] with x, or -1
  function automatic int firstOf(ref bit xh[$], input int lo, input int hi);
    for (int u = lo; u <= hi; ++u) if (xh[u]) return u;
    return -1;
  endfunction
  function automatic int passTick(int k, int s);
    case (k)
      0: return !ah[s] ? s : firstOf(bh, s + 1, s + 2);
      1: return !ah[s] ? s : firstOf(bh, s + 2, s + 3);
      2: return !ah[s] ? s : !bh[s] ? -1 : firstOf(ch, s + 1, s + 3);
      3: return !ah[s] ? s : firstOf(bh, s, s + 2);
      4: return !ah[s] ? s : !bh[s + 1] ? -1 : firstOf(ch, s + 2, s + 3);
      5: return !ah[s] ? s : !dh[s + 1] ? s + 1 : firstOf(ch, s + 2, s + 3);
      6: return !ah[s] ? -1 : firstOf(bh, s + 1, s + 2);
      8: return !ah[s] ? s : !bh[s] ? -1 : ch[s + 1] ? s + 1 : -1;
      default: return -1;
    endcase
  endfunction
  // Disabled attempts neither pass nor fail (IEEE 1800-2023 16.12)
  function automatic int passTickDisabled(int s);
    automatic int t = passTick(0, s);
    for (int u = s; u <= (t < 0 ? s + 2 : t); ++u) if (rh[u]) return -1;
    return t;
  endfunction

  initial begin
    int last;
    int expn[9];
    repeat (300) @(negedge clk);
    last = ah.size() - 1;
    for (int k = 0; k < 9; ++k) begin
      for (int s = 0; s <= last; ++s) begin
        automatic int t = k == 7 ? passTickDisabled(s) : passTick(k, s);
        if (t >= 0 && t <= last) ++expn[k];
      end
    end
    for (int k = 0; k < 9; ++k) begin
      if (k == 7) continue;
      `checkd(n[k], expn[k]);
    end
    `checkd(n[7], expn[7]);
    `checkd(n[9] > 0, 1'b1);
    for (int k = 0; k < 5; ++k) `checkd(m[k] > 0, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
