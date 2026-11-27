// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A property 'and' of a boolean and an implication, or its negation, fails at once without the
// boolean, and otherwise as the other operand does (IEEE 1800-2023 16.12.5). The implication
// passes vacuously without its antecedent, fails on the first failing check of its consequent,
// and passes at its end (16.12.7); the negation the other way round (16.12.3). Each attempt is
// checked on the tick it resolves, also with the booleans of nested 'and's conjoined.

module t (
    input clk
);
  localparam int END = 200;
  localparam int NPROP = 8;

  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];
  wire d = crc[21] | crc[25];
  bit ha[END + 4], hb[END + 4], hc[END + 4], hd[END + 4];
  int passes[NPROP][END + 4];
  int fails[NPROP][END + 4];
  // The tick of an action, whether it runs before or after the update of cyc
  int tick = 0;
  always @(negedge clk) tick = cyc;

  assert property (@(posedge clk) disable iff (cyc > END) c and not (a |=> b))
    ++passes[0][tick];
  else ++fails[0][tick];
  assert property (@(posedge clk) disable iff (cyc > END) not (a |-> ##1 b) and c)
    ++passes[1][tick];
  else ++fails[1][tick];
  assert property (@(posedge clk) disable iff (cyc > END) c and not (a |-> b ##1 b))
    ++passes[2][tick];
  else ++fails[2][tick];
  assert property (@(posedge clk) disable iff (cyc > END) c and (a |=> b)) ++passes[3][tick];
  else ++fails[3][tick];
  assert property (@(posedge clk) disable iff (cyc > END) (a |-> ##1 b) and c)
    ++passes[4][tick];
  else ++fails[4][tick];
  assert property (@(posedge clk) disable iff (cyc > END) c and (a |-> b ##1 b))
    ++passes[5][tick];
  else ++fails[5][tick];
  assert property (@(posedge clk) disable iff (cyc > END) c and (a |=> b) and d)
    ++passes[6][tick];
  else ++fails[6][tick];
  assert property (@(posedge clk) disable iff (cyc > END) d and not (a |-> ##1 b) and c)
    ++passes[7][tick];
  else ++fails[7][tick];

  // Model of the attempt from s, whose consequent checks b on ticks s + first to s + last,
  // negated or not, and whose boolean is c, and d with withd
  task automatic expect_attempt(int s, int first, int last, bit negated, bit withd,
                                inout int p[END + 4], inout int f[END + 4]);
    if (!hc[s] || (withd && !hd[s])) begin
      ++f[s];
      return;
    end
    if (!ha[s]) begin
      if (negated) ++f[s];
      else ++p[s];
      return;
    end
    for (int k = first; k <= last; ++k) begin
      if (!hb[s+k]) begin
        if (negated) ++p[s+k];
        else ++f[s+k];
        return;
      end
    end
    if (negated) ++f[s+last];
    else ++p[s+last];
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc <= END + 3) begin
      ha[cyc] = a;
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = d;
    end
    if (cyc == END + 3) begin
      for (int i = 0; i < NPROP; ++i) begin
        automatic int p[END + 4];
        automatic int f[END + 4];
        automatic int np = 0, nf = 0;
        for (int t = 0; t < END + 4; ++t) begin
          p[t] = 0;
          f[t] = 0;
        end
        for (int s = 0; s <= END; ++s) begin
          if (i == 2 || i == 5) expect_attempt(s, 0, 1, i < 3, 0, p, f);
          else expect_attempt(s, 1, 1, i < 3 || i == 7, i >= 6, p, f);
        end
        for (int t = 0; t <= END; ++t) begin
          `checkd(passes[i][t], p[t]);
          `checkd(fails[i][t], f[t]);
          np += p[t];
          nf += f[t];
        end
        if (np == 0 || nf == 0) `stop;
      end
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
