// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A property 'or' holds when an operand holds (IEEE 1800-2023 16.12.4), and an implication
// holds vacuously when its antecedent does not match (16.12.7), so 'd or (b |-> p)' passes on
// a tick with d and b false. Checked against a model of each attempt.

module t (
    input clk
);
  localparam int END = 240;
  localparam int NPROP = 3;

  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire b = crc[0] | crc[3];
  wire c = crc[5] | crc[9];
  wire d = crc[13] & crc[17];
  bit hb[END + 4], hc[END + 4], hd[END + 4];
  int passes[NPROP][END + 4];
  int fails[NPROP][END + 4];
  // The tick of an action, whether it runs before or after the update of cyc
  int tick = 0;
  always @(negedge clk) tick = cyc;

  // A directed lane: d and b false for 5 ticks, then d true for 3 ticks
  int p_dir = 0, f_dir = 0;
  wire bd = 1'b0;
  wire cd = 1'b0;
  wire dd = cyc >= 5;
  assert property (@(posedge clk) disable iff (cyc >= 8) dd or (bd |-> always [0:1] cd))
    ++p_dir;
  else ++f_dir;

  assert property (@(posedge clk) disable iff (cyc > END) d or (b |-> always [0:0] c))
    ++passes[0][tick];
  else ++fails[0][tick];
  assert property (@(posedge clk) disable iff (cyc > END) d or (b |-> always [0:1] c))
    ++passes[1][tick];
  else ++fails[1][tick];
  assert property (@(posedge clk) disable iff (cyc > END) d or (b |=> always [0:1] c))
    ++passes[2][tick];
  else ++fails[2][tick];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 10) begin
      `checkd(p_dir, 8);
      `checkd(f_dir, 0);
    end
    if (cyc <= END + 3) begin
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = d;
    end
    if (cyc == END + 3) begin
      for (int i = 0; i < NPROP; ++i) begin
        automatic int p[END + 4];
        automatic int f[END + 4];
        automatic int last = i == 0 ? 0 : 1;
        automatic int first = i == 2 ? 1 : 0;
        for (int t = 0; t < END + 4; ++t) begin
          p[t] = 0;
          f[t] = 0;
        end
        // The attempt from s passes on s with d or without b, and otherwise fails on the
        // first tick c is false, or passes at the end
        for (int s = 0; s <= END; ++s) begin
          automatic bit done = 0;
          if (hd[s] || !hb[s]) begin
            ++p[s];
            done = 1;
          end
          for (int k = first; k <= first + last && !done; ++k) begin
            if (!hc[s+k]) begin
              ++f[s+k];
              done = 1;
            end
          end
          if (!done) ++p[s+first+last];
        end
        for (int t = 0; t <= END; ++t) begin
          // Known limit: the attempts passing on one tick, started on different ticks, run
          // the pass action once there, where IEEE 1800-2023 16.14.1 runs it p[t] times
          `checkd(passes[i][t], int'(p[t] > 0));
          `checkd(fails[i][t], f[t]);
        end
      end
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
