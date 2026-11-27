// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An asserted property 'or' fails once both its operands have failed (IEEE 1800-2023 16.12.4),
// against a model of each attempt, with a boolean operand or bounded 'always' operands

module t (
    input clk
);
  localparam int END = 300;

  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire a = crc[0] | crc[3] | crc[7];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];
  wire d = crc[21];
  bit ha[END + 4], hb[END + 4], hc[END + 4], hd[END + 4];

  int n_fail1 = 0, n_fail2 = 0, n_fail3 = 0, n_fail4 = 0, n_fail5 = 0, n_fail6 = 0;
  int n_fail7 = 0, n_fail8 = 0, n_fail9 = 0, n_fail10 = 0, n_fail11 = 0, n_fail12 = 0;
  int n_fail13 = 0, n_fail14 = 0, n_fail15 = 0, n_pass16 = 0;

  // An implication with a boolean operand
  assert property (@(posedge clk) disable iff (cyc > END) (a |-> ##1 b) or c)
  else ++n_fail1;
  // A bounded weak always with a boolean, a sequence or another always
  assert property (@(posedge clk) disable iff (cyc > END) (always [0:1] a) or d)
  else ++n_fail2;
  assert property (@(posedge clk) disable iff (cyc > END) (always [0:1] a) or (b ##1 c))
  else ++n_fail3;
  assert property (@(posedge clk) disable iff (cyc > END) (always [0:1] a) or (always [0:1] b))
  else ++n_fail4;
  // A strong always with a boolean
  assert property (@(posedge clk) disable iff (cyc > END) d or (s_always [0:1] a))
  else ++n_fail5;
  // Strong always of three and four ticks, in either order
  assert property (@(posedge clk) disable iff (cyc > END) d or (s_always [0:2] a))
  else ++n_fail7;
  assert property (@(posedge clk) disable iff (cyc > END) d or (s_always [0:3] a))
  else ++n_fail8;
  assert property (@(posedge clk) disable iff (cyc > END) (s_always [0:2] a) or d)
  else ++n_fail9;
  assert property (@(posedge clk) disable iff (cyc > END) !a or (s_always [0:2] a))
  else ++n_fail10;
  // An implication in the other operand of a boolean keeps the operand split off behind the
  // boolean, where a delay ring counts the attempts failing on one tick once (known limit)
  assert property (@(posedge clk) disable iff (cyc > END) d or (b |-> always [0:2] a))
  else ++n_fail13;
  assert property (@(posedge clk) disable iff (cyc > END) d or (b |=> s_always [0:3] a))
  else ++n_fail14;
  assert property (@(posedge clk) disable iff (cyc > END) d or (b |-> always [1:3] a))
  else ++n_fail15;
  // The attempts passing on one tick pass once (known limit)
  assert property (@(posedge clk) disable iff (cyc > END) d or (always [0:1] a)) ++n_pass16;
  else begin
  end
  // Two bounded always after an implication, and a weak and a strong always
  assert property (@(posedge clk) disable iff (cyc > END)
                   a |-> ((always [0:1] b) or (always [0:2] c)))
  else ++n_fail11;
  assert property (@(posedge clk) disable iff (cyc > END) (always [0:0] a) or (s_always [2:2] b))
  else ++n_fail12;
  // An implication ending in a repetition with a boolean
  assert property (@(posedge clk) disable iff (cyc > END) d or (b |-> ##1 a [*2]))
  else ++n_fail6;

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
      automatic int e1 = 0, e2 = 0, e3 = 0, e4 = 0, e5 = 0, e6 = 0, e7 = 0, e8 = 0, e10 = 0;
      automatic int e11 = 0, e12 = 0, e13 = 0, e14 = 0, e15 = 0, p16 = 0;
      automatic bit passAt[END + 4];
      // Count the failures of attempts started on cycle s on the cycles they fail, up to END
      for (int s = 0; s <= END; ++s) begin
        if (!hc[s] && ha[s] && !hb[s+1] && s < END) ++e1;
        if (!hd[s] && !ha[s]) ++e2;
        else if (!hd[s] && !ha[s+1] && s < END) ++e2;
        if (!ha[s] && !hb[s]) ++e3;
        else if (!(ha[s] && ha[s+1]) && !(hb[s] && hc[s+1]) && s < END) ++e3;
        if (!ha[s] && !hb[s]) ++e4;
        else if (!(ha[s] && ha[s+1]) && !(hb[s] && hb[s+1]) && s < END) ++e4;
        if (!hd[s] && !ha[s]) ++e5;
        else if (!hd[s] && !ha[s+1] && s < END) ++e5;
        if (!hd[s] && hb[s] && !ha[s+1] && s < END) ++e6;
        else if (!hd[s] && hb[s] && !ha[s+2] && s + 1 < END) ++e6;
        // A strong always fails on the first tick of its range without a, up to END
        for (int k = 0; k <= 3; ++k) begin
          if (!ha[s+k]) begin
            if (!hd[s] && k <= 2 && s + k <= END) ++e7;
            if (!hd[s] && s + k <= END) ++e8;
            if (ha[s] && k <= 2 && s + k <= END) ++e10;
            break;
          end
        end
        // Both operands fail, the later on its first tick without b or c, up to END
        if (ha[s]) begin
          automatic int fb = !hb[s] ? 0 : !hb[s+1] ? 1 : -1;
          automatic int fc = !hc[s] ? 0 : !hc[s+1] ? 1 : !hc[s+2] ? 2 : -1;
          if (fb >= 0 && fc >= 0 && s + (fb > fc ? fb : fc) <= END) ++e11;
        end
        if (!ha[s] && !hb[s+2] && s + 2 <= END) ++e12;
        // Each attempt fails on its first tick without a, up to END
        if (!hd[s] && hb[s]) begin
          for (int k = 0; k <= 2; ++k) begin
            if (!ha[s+k]) begin
              if (s + k <= END) ++e13;
              break;
            end
          end
          for (int k = 1; k <= 4; ++k) begin
            if (!ha[s+k]) begin
              if (s + k <= END) ++e14;
              break;
            end
          end
          for (int k = 1; k <= 3; ++k) begin
            if (!ha[s+k]) begin
              if (s + k <= END) ++e15;
              break;
            end
          end
        end
        // An attempt passes on its tick with d, or else on the next with a on both
        if (hd[s]) passAt[s] = 1'b1;
        else if (ha[s] && ha[s+1] && s < END) passAt[s+1] = 1'b1;
      end
      `checkd(n_fail1, e1);
      `checkd(n_fail2, e2);
      `checkd(n_fail3, e3);
      `checkd(n_fail4, e4);
      `checkd(n_fail5, e5);
      `checkd(n_fail6, e6);
      `checkd(n_fail7, e7);
      `checkd(n_fail8, e8);
      `checkd(n_fail9, e7);
      `checkd(n_fail10, e10);
      `checkd(n_fail11, e11);
      `checkd(n_fail12, e12);
      // Each attempt failing would give e13, e14 and e15: 33, 44 and 35
      `checkd(e13, 33);
      `checkd(e14, 44);
      `checkd(e15, 35);
      `checkd(n_fail13, 28);
      `checkd(n_fail14, 32);
      `checkd(n_fail15, 29);
      // Once for each tick with a pass
      foreach (passAt[t]) p16 += passAt[t];
      `checkd(n_pass16, p16);
      if (e1 == 0 || e2 == 0 || e3 == 0 || e4 == 0 || e5 == 0 || e6 == 0 || e10 == 0 || e11 == 0
          || e12 == 0)
        `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
