// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// 'within' per attempt: an attempt matches when its outer sequence matches with a match of the
// inner sequence inside it, and fails once no such match remains (IEEE 1800-2023 16.9.10)

module t (
    input clk
);
  localparam int NCYC = 300;
  localparam int NPROP = 7;

  integer cyc = 0;
  reg [63:0] crc = 64'h5aa5_0f0f_3c3c_9696;

  wire a = crc[0];
  wire b = crc[1];
  wire c = crc[2];
  wire d = crc[3];
  wire e = crc[4] | crc[9];

  bit ha[NCYC + 8];
  bit hb[NCYC + 8];
  bit hc[NCYC + 8];
  bit hd[NCYC + 8];
  bit he[NCYC + 8];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hd[cyc] = d;
    he[cyc] = e;
  end

  int passes[NPROP];
  int fails[NPROP];

  // verilog_format: off
  assert property (@(posedge clk) (b ##1 c) within (a ##3 d)) ++passes[0];
  else ++fails[0];
  cover property (@(posedge clk) (b ##1 c) within (a ##3 d)) ++passes[1];
  assert property (@(posedge clk) (b ##[1:2] c) within (a ##[2:4] d)) ++passes[2];
  else ++fails[2];
  cover property (@(posedge clk) (b ##[1:2] c) within (a ##[2:4] d)) ++passes[3];
  assert property (@(posedge clk) e |-> ((b ##1 c) within (a ##3 d))) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) ((b ##1 c) within (a ##3 d)) ##1 e) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) ((b ##1 c) within (a ##3 d)) or (d ##1 e)) ++passes[6];
  else ++fails[6];
  // verilog_format: on

  // A match of b ##[1:minDelay..maxDelay] c starting and ending in [from, to]
  function automatic bit innerIn(int from, int to, int minDelay, int maxDelay);
    for (int p = from; p <= to; ++p) begin
      for (int k = minDelay; k <= maxDelay; ++k) begin
        if (p + k <= to && hb[p] && hc[p+k]) return 1;
      end
    end
    return 0;
  endfunction

  // The earliest tick (b ##[1:innerMax] c) within (a ##[outerMin:outerMax] d) started on s
  // matches, or -1
  function automatic int withinMatch(int s, int innerMax, int outerMin, int outerMax);
    if (!ha[s]) return -1;
    for (int t = s + outerMin; t <= s + outerMax; ++t) begin
      if (hd[t] && innerIn(s, t, 1, innerMax)) return t;
    end
    return -1;
  endfunction

  localparam int PASS = 1;
  localparam int FAIL = 2;

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    int m;
    case (i)
      0, 1: begin
        m = withinMatch(s, 1, 3, 3);
        tick = m >= 0 ? m : ha[s] ? s + 3 : s;
        outcome = m >= 0 ? PASS : FAIL;
      end
      2, 3: begin
        m = withinMatch(s, 2, 2, 4);
        tick = m >= 0 ? m : ha[s] ? s + 4 : s;
        outcome = m >= 0 ? PASS : FAIL;
      end
      4: begin
        m = withinMatch(s, 1, 3, 3);
        tick = !he[s] ? s : m >= 0 ? m : ha[s] ? s + 3 : s;
        outcome = !he[s] || m >= 0 ? PASS : FAIL;
      end
      5: begin
        m = withinMatch(s, 1, 3, 3);
        tick = m >= 0 ? m + 1 : ha[s] ? s + 3 : s;
        outcome = m >= 0 && he[m+1] ? PASS : FAIL;
      end
      default: begin
        // The 'or' passes on its first success, else fails with its last operand
        m = withinMatch(s, 1, 3, 3);
        if (hd[s] && he[s+1] && (m < 0 || m > s + 1)) begin
          tick = s + 1;
          outcome = PASS;
        end
        else if (m >= 0) begin
          tick = m;
          outcome = PASS;
        end
        else begin
          tick = ha[s] ? s + 3 : hd[s] ? s + 1 : s;
          outcome = FAIL;
        end
      end
    endcase
  endtask

  // Check the actions of the attempts resolving by tick last
  task automatic check_actions(int last);
    for (int i = 0; i < NPROP; ++i) begin
      int expPasses = 0;
      int expFails = 0;
      for (int s = 0; s <= last; ++s) begin
        int outcome;
        int tick;
        expect_attempt(i, s, outcome, tick);
        if (tick > last) continue;
        if (outcome == FAIL) ++expFails;
        else ++expPasses;
      end
      `checkd(passes[i], expPasses);
      // A cover runs no action on a failure
      if (i != 1 && i != 3) `checkd(fails[i], expFails);
    end
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Between ticks, after the actions of the previous tick
  always @(negedge clk) begin
    if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
