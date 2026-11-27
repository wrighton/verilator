// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A property operator over sequences with local variables gives each attempt one outcome
// (IEEE 1800-2023 16.10, 16.14.1), also where an attempt assigns a variable on a tick that
// depends on its match, or reassigns it; each read is a fixed number of ticks after its
// assignment. The burst lane starts its attempts on three ticks in five.

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
  wire [1:0] x = crc[38:37];
  wire [1:0] y = crc[42:41];
  wire g = (cyc % 5) < 3;

  bit ha[NCYC + 4];
  bit hb[NCYC + 4];
  bit hc[NCYC + 4];
  bit hd[NCYC + 4];
  bit he[NCYC + 4];
  bit hg[NCYC + 4];
  bit [1:0] hx[NCYC + 4];
  bit [1:0] hy[NCYC + 4];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hd[cyc] = d;
    he[cyc] = e;
    hg[cyc] = g;
    hx[cyc] = x;
    hy[cyc] = y;
  end

  int passes[NPROP];
  int fails[NPROP];

  // verilog_format: off
  sequence s_lv(start);
    logic [1:0] v;
    (start, v = x) ##1 (b && y == v);
  endsequence
  // Assigned after a run of a of 1 to 3 ticks
  sequence s_run;
    logic [1:0] v;
    (a [* 1:3] ##0 (1, v = x)) ##1 (b && y == v);
  endsequence
  // Assigned 1 or 2 ticks after a
  sequence s_range;
    logic [1:0] v;
    a ##[1:2] (c, v = x) ##1 (y == v);
  endsequence
  // Reassigned
  sequence s_again;
    logic [1:0] v;
    (a, v = x) ##1 (b, v = v + 1) ##1 (c, v = v + 1) ##1 (y == v);
  endsequence

  assert property (@(posedge clk) s_lv(a) or (d ##2 e)) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) not (s_lv(a) or (d ##2 e))) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) (s_lv(a) |-> c) and (d |-> e)) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) not (s_lv(a) ##[0:1] c)) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) s_run) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) not s_range) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) s_again or (d ##2 e)) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) s_lv(g) or (d ##2 e)) ++passes[7];
  else ++fails[7];
  // verilog_format: on

  // s_lv from s: whether it matches, and the tick it resolves on
  task automatic lv(bit start, int s, output bit match, output int tick);
    match = start && hb[s+1] && hy[s+1] == hx[s];
    tick = start ? s + 1 : s;
  endtask

  // A sequence 'or' passes on its first match, else fails on its last thread's end
  task automatic either(bit m1, int t1, bit m2, int t2, output bit pass, output int tick);
    pass = m1 || m2;
    if (m1 && m2) tick = t1 < t2 ? t1 : t2;
    else if (m1) tick = t1;
    else if (m2) tick = t2;
    else tick = t1 > t2 ? t1 : t2;
  endtask

  // Whether the attempt of property i started on tick s passes, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output bit pass, output int tick);
    bit m1;
    int t1;
    const bit m2 = hd[s] && he[s+2];
    const int t2 = hd[s] ? s + 2 : s;
    case (i)
      0, 1, 7: begin
        lv(i == 7 ? hg[s] : ha[s], s, m1, t1);
        either(m1, t1, m2, t2, pass, tick);
        if (i == 1) pass = !pass;
      end
      2: begin
        // Fails on its first failing operand, else passes on its last
        bit pl;
        bit pr;
        lv(ha[s], s, m1, t1);
        pl = !m1 || hc[s+1];
        pr = !hd[s] || he[s];
        if (!pl && !pr) begin
          pass = 0;
          tick = s;
        end
        else if (!pl) begin
          pass = 0;
          tick = t1;
        end
        else if (!pr) begin
          pass = 0;
          tick = s;
        end
        else begin
          pass = 1;
          tick = t1;
        end
      end
      3: begin
        // The negation fails on the first match of s_lv ##[0:1] c
        lv(ha[s], s, m1, t1);
        pass = 1;
        tick = m1 ? s + 2 : t1;
        if (m1 && hc[s+1]) begin
          pass = 0;
          tick = s + 1;
        end
        else if (m1 && hc[s+2]) begin
          pass = 0;
          tick = s + 2;
        end
      end
      4: begin
        // An end of a[*1:3] on s + k assigns x of s + k, read on s + k + 1
        int run = 0;
        while (run < 3 && ha[s+run]) ++run;
        pass = 0;
        tick = s + run;
        for (int k = run - 1; k >= 0; --k) begin
          if (hb[s+k+1] && hy[s+k+1] == hx[s+k]) begin
            pass = 1;
            tick = s + k + 1;
          end
        end
      end
      5: begin
        // c on s + k assigns x of s + k, read on s + k + 1; the negation fails on a match
        pass = 1;
        tick = s;
        if (ha[s]) begin
          tick = hc[s+2] ? s + 3 : hc[s+1] ? s + 2 : s + 2;
          if (hc[s+2] && hy[s+3] == hx[s+2]) begin
            pass = 0;
            tick = s + 3;
          end
          if (hc[s+1] && hy[s+2] == hx[s+1]) begin
            pass = 0;
            tick = s + 2;
          end
        end
      end
      default: begin
        // x of s, plus one on s + 1 and on s + 2, read on s + 3
        bit [1:0] v = hx[s] + 2'd2;
        m1 = ha[s] && hb[s+1] && hc[s+2] && hy[s+3] == v;
        t1 = !ha[s] ? s : !hb[s+1] ? s + 1 : !hc[s+2] ? s + 2 : s + 3;
        either(m1, t1, m2, t2, pass, tick);
      end
    endcase
  endtask

  // Check the actions of the attempts resolving by tick last
  task automatic check_actions(int last);
    for (int i = 0; i < NPROP; ++i) begin
      int expPasses = 0;
      int expFails = 0;
      for (int s = 0; s <= last; ++s) begin
        bit pass;
        int tick;
        expect_attempt(i, s, pass, tick);
        if (tick > last) continue;
        if (pass) ++expPasses;
        else ++expFails;
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
