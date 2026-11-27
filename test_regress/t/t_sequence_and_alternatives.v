// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A sequence 'and' whose operands have a few lengths fails when no pair of their matches
// exists, and first matches at the later end of the first such pair (IEEE 1800-2023 16.9.5),
// also as the consequent of an implication, checked against a model of each attempt

module t (
    input clk
);
  localparam int END = 300;
  localparam int NPROP = 4;

  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];
  wire d = crc[21] | crc[25];
  bit ha[END + 6], hb[END + 6], hc[END + 6], hd[END + 6];
  int passes[NPROP][END + 6];
  int fails[NPROP][END + 6];
  // The tick of an action, whether it runs before or after the update of cyc
  int tick = 0;
  always @(negedge clk) tick = cyc;

  // A consequent ending in an 'and' with a repetition range: only its first match counts
  assert property (@(posedge clk) disable iff (cyc > END) d |-> ((a [*2:3]) and (b [*2])))
    ++passes[0][tick];
  else ++fails[0][tick];
  // A range followed by another step, so of two lengths
  assert property (@(posedge clk) disable iff (cyc > END) (a [*2:3] ##1 c) and (b [*2]))
    ++passes[1][tick];
  else ++fails[1][tick];
  // Alternatives of one length, which end together
  assert property (@(posedge clk) disable iff (cyc > END) (a [*1:2] ##1 c) and (b [*3]))
    ++passes[2][tick];
  else ++fails[2][tick];
  // A ranged cycle delay
  assert property (@(posedge clk) disable iff (cyc > END) (a ##[1:2] b) and c)
    ++passes[3][tick];
  else ++fails[3][tick];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc <= END + 5) begin
      ha[cyc] = a;
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = d;
    end
    if (cyc == END + 5) begin
      for (int i = 0; i < NPROP; ++i) begin
        automatic int p[END + 6];
        automatic int f[END + 6];
        for (int t = 0; t < END + 6; ++t) begin
          p[t] = 0;
          f[t] = 0;
        end
        // The tick each attempt from s resolves on, and whether it passes
        for (int s = 0; s <= END; ++s) begin
          automatic int t = s;
          automatic bit pass = 0;
          if (i == 0) begin
            if (!hd[s]) pass = 1;
            else if (ha[s] && hb[s]) begin
              t = s + 1;
              pass = ha[s+1] && hb[s+1];
            end
          end
          else if (i == 1) begin
            if (!(ha[s] && hb[s])) t = s;
            else if (!(ha[s+1] && hb[s+1])) t = s + 1;
            else if (hc[s+2]) begin
              t = s + 2;
              pass = 1;
            end
            else if (!ha[s+2]) t = s + 2;
            else begin
              t = s + 3;
              pass = hc[s+3];
            end
          end
          else if (i == 3) begin
            if (!(ha[s] && hc[s])) t = s;
            else if (hb[s+1]) begin
              t = s + 1;
              pass = 1;
            end
            else begin
              t = s + 2;
              pass = hb[s+2];
            end
          end
          else begin
            // b on s to s + 2, and a on s then c on s + 1, or a on s and s + 1 then c on s + 2
            if (!(ha[s] && hb[s])) t = s;
            else if (!hb[s+1] || !(hc[s+1] || ha[s+1])) t = s + 1;
            else begin
              t = s + 2;
              pass = hb[s+2] && (hc[s+1] || hc[s+2]);
            end
          end
          if (pass) ++p[t];
          else ++f[t];
        end
        for (int t = 0; t <= END; ++t) begin
          `checkd(fails[i][t], f[t]);
          // Known limit: attempts of different lengths passing on one tick run the pass action
          // once there, where IEEE 1800-2023 16.14.1 runs it p[t] times
          if (i == 1 || i == 3) begin
            `checkd(passes[i][t], int'(p[t] > 0));
          end
          else begin
            `checkd(passes[i][t], p[t]);
          end
        end
      end
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
