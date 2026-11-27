// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An antecedent match on the first tick of a ranged cycle delay starts the consequent
// (IEEE 1800-2023 16.12.7), so its failure is reported

module t (
    input clk
);

  localparam int END = 300;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  // Directed: the antecedent matches only at its earlier end, on tick 1
  wire da = cyc == 0;
  wire db = cyc == 1;
  int dpass = 0, dfail = 0;
  assert property (@(posedge clk) disable iff (cyc > 5) (da ##[1:2] db) |-> 1'b0) ++dpass;
  else ++dfail;
  // Directed: the antecedent matches on both ends of the range, ticks 6 and 7, and each match
  // fails the consequent, also a strong 'always' over later ticks
  int dfail2 = 0, dfail3 = 0;
  assert property (@(posedge clk) (cyc == 5) ##[1:2] 1'b1 |-> (cyc == 100))
  else ++dfail2;
  assert property (@(posedge clk) (cyc == 5) ##[1:2] 1'b1 |-> s_always [2:3] (cyc == 100))
  else ++dfail3;

  // Random
  wire a = crc[0] & crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] & crc[17];
  wire g = crc[21] | crc[25];
  bit ha[END + 4];
  bit hb[END + 4];
  bit hc[END + 4];
  bit hg[END + 4];
  int fails = 0, gfails = 0;
  assert property (@(posedge clk) disable iff (cyc > END) (a ##[1:2] b) |-> c)
  else ++fails;
  // Guarded on every tick of the match, also its first eligible one
  assert property (@(posedge clk) disable iff (cyc > END) (g throughout (a ##[1:2] b)) |-> c)
  else ++gfails;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc <= END + 3) begin
      ha[cyc] = a;
      hb[cyc] = b;
      hc[cyc] = c;
      hg[cyc] = g;
    end
    if (cyc == 8) begin
      `checkd(dpass, 5);
      `checkd(dfail, 1);
    end
    if (cyc == 12) begin
      `checkd(dfail2, 2);
      `checkd(dfail3, 2);
    end
    if (cyc == END + 3) begin
      automatic int expFails = 0, expGFails = 0;
      // Known limit: one failure per tick with a failing antecedent match, as the attempts and
      // the matches of one attempt are not told apart, where IEEE 1800-2023 16.14.1 has one
      // per failing attempt
      for (int t = 1; t <= END; ++t) begin
        if (hb[t] && !hc[t] && (ha[t-1] || (t >= 2 && ha[t-2]))) ++expFails;
        if (hb[t] && !hc[t] && hg[t] && hg[t-1]
            && (ha[t-1] || (t >= 2 && ha[t-2] && hg[t-2])))
          ++expGFails;
      end
      `checkd(fails, expFails);
      `checkd(gfails, expGFails);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
