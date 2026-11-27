// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An asserted sequence 'or' passes on the first match of an attempt, and fails once no operand
// can match (IEEE 1800-2023 16.9.7, 16.14.1), also where attempts of operands of different
// lengths resolve on one tick

module t (
    input clk
);
  localparam int NCYC = 300;
  localparam int NPROP = 8;

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef_0c8d_d70a_4497;

  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];
  wire d = crc[21] | crc[25];
  wire e = crc[29] | crc[33];

  bit ha[NCYC + 4];
  bit hb[NCYC + 4];
  bit hc[NCYC + 4];
  bit hd[NCYC + 4];
  bit he[NCYC + 4];
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
  assert property (@(posedge clk) (a ##1 b) or (c ##2 d)) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) not ((a ##1 b) or (c ##2 d))) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) (a ##[1:2] b) or c) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) (a ##1 b) or (c ##2 d) or (e ##3 a)) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) not (not ((c ##2 d) or b))) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) not ((a ##1 b) or (a ##[2:3] c))) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) not ((##1 a) or (##2 b) or (##3 c) or (##4 a) or (##5 b)))
    ++passes[7];
  else ++fails[7];
  // Operands of one length, lowered by the NFA
  assert property (@(posedge clk) (a ##1 b) or (c ##1 d)) ++passes[5];
  else ++fails[5];
  // verilog_format: on

  localparam int PASS = 1;
  localparam int FAIL = 2;

  // An operand x ##k y from s: whether it matches, and the tick it resolves on
  task automatic operand(bit x, bit y, int s, int k, output bit match, output int tick);
    match = x && y;
    tick = x ? s + k : s;
  endtask

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    bit m[5];
    int t[5];
    int n = 2;
    bit any = 0;
    int first = 0;
    int last = 0;
    case (i)
      0, 1, 5: begin
        operand(ha[s], hb[s+1], s, 1, m[0], t[0]);
        if (i == 5) operand(hc[s], hd[s+1], s, 1, m[1], t[1]);
        else operand(hc[s], hd[s+2], s, 2, m[1], t[1]);
      end
      2: begin
        // a ##[1:2] b first matches on s + 1, else on s + 2
        m[0] = ha[s] && (hb[s+1] || hb[s+2]);
        t[0] = !ha[s] ? s : hb[s+1] ? s + 1 : s + 2;
        m[1] = hc[s];
        t[1] = s;
      end
      3: begin
        n = 3;
        operand(ha[s], hb[s+1], s, 1, m[0], t[0]);
        operand(hc[s], hd[s+2], s, 2, m[1], t[1]);
        operand(he[s], ha[s+3], s, 3, m[2], t[2]);
      end
      6: begin
        operand(ha[s], hb[s+1], s, 1, m[0], t[0]);
        m[1] = ha[s] && (hc[s+2] || hc[s+3]);
        t[1] = !ha[s] ? s : hc[s+2] ? s + 2 : s + 3;
      end
      7: begin
        n = 5;
        m[0] = ha[s+1];
        m[1] = hb[s+2];
        m[2] = hc[s+3];
        m[3] = ha[s+4];
        m[4] = hb[s+5];
        for (int k = 0; k < 5; ++k) t[k] = s + k + 1;
      end
      default: begin
        operand(hc[s], hd[s+2], s, 2, m[0], t[0]);
        m[1] = hb[s];
        t[1] = s;
      end
    endcase
    for (int k = 0; k < n; ++k) begin
      if (m[k] && (!any || t[k] < first)) first = t[k];
      if (m[k]) any = 1;
      if (t[k] > last) last = t[k];
    end
    tick = any ? first : last;
    outcome = any ? PASS : FAIL;
    // The negation swaps them
    if (i == 1 || i >= 6) outcome = any ? FAIL : PASS;
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
      `checkd(fails[i], expFails);
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
