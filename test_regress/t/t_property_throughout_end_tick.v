// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The guard of a throughout holds on every tick of a match, the last one included, also over
// a within, intersect or and (IEEE 1800-2023 16.9.9), checked per attempt against a reference
// model. Every sequence here lasts four ticks, so the attempt passing or covered on a tick is
// the one that started three ticks before. Under the within, which is covered only, only
// attempts whose guard drops are checked.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk = 0;
  always #5 clk = !clk;

  localparam int CYCLES = 1000;
  localparam int LEN = 4;
  int cyc = 0;
  int tick = 0;  // Changes away from the ticks, so actions read the tick of their attempt
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire run = cyc >= 2 && cyc < CYCLES;
  wire a = run && (crc[1] | crc[2]);
  wire b = run && (crc[5] | crc[6]);
  wire c = run && (crc[9] | crc[10]);
  wire d = run && (crc[13] | crc[14]);
  wire e = run && (crc[17] | crc[18] | crc[19]);

  bit ah[CYCLES + 8], bh[CYCLES + 8], ch[CYCLES + 8], dh[CYCLES + 8], eh[CYCLES + 8];
  always @(posedge clk) begin
    ah[cyc] = a;
    bh[cyc] = b;
    ch[cyc] = c;
    dh[cyc] = d;
    eh[cyc] = e;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end
  always @(negedge clk) tick = cyc;

  // Ticks on which each assertion passed
  bit passSeq[CYCLES + 8], passIntersect[CYCLES + 8], passAnd[CYCLES + 8];
  assert property (@(posedge clk) e throughout (a ##3 d)) passSeq[tick] = 1;
  else $write("");
  assert property (@(posedge clk) e throughout ((a ##3 d) intersect (a ##1 b ##2 d)))
    passIntersect[tick] = 1;
  else $write("");
  assert property (@(posedge clk) e throughout ((a ##1 b ##1 c ##1 d) and (a ##3 d)))
    passAnd[tick] = 1;
  else $write("");
  bit coverSeq[CYCLES + 8], coverWithin[CYCLES + 8];
  cover property (@(posedge clk) e throughout (a ##3 d)) coverSeq[tick] = 1;
  cover property (@(posedge clk) e throughout ((b ##1 c) within (a ##3 d))) coverWithin[tick] = 1;

  // True if e holds on every tick of the attempt started on tick s
  function automatic bit eHolds(int s);
    for (int k = 0; k < LEN; k++) if (!eh[s+k]) return 0;
    return 1;
  endfunction
  function automatic bit outerMatches(int s);
    return ah[s] && dh[s+3];
  endfunction
  function automatic bit refSeq(int s);
    return eHolds(s) && outerMatches(s);
  endfunction
  function automatic bit refIntersect(int s);
    return eHolds(s) && outerMatches(s) && bh[s+1];
  endfunction
  function automatic bit refAnd(int s);
    return eHolds(s) && outerMatches(s) && bh[s+1] && ch[s+2];
  endfunction

  int endDrops = 0;
  int last;
  always @(negedge clk) begin
    if (cyc == CYCLES + 8) begin
      for (int s = 0; s + LEN - 1 < CYCLES + 8; s++) begin
        last = s + LEN - 1;
        `checkd(passSeq[last], refSeq(s));
        `checkd(coverSeq[last], refSeq(s));
        if (!eHolds(s)) `checkd(coverWithin[last], 1'b0);
        `checkd(passIntersect[last], refIntersect(s));
        `checkd(passAnd[last], refAnd(s));
        // Attempts matching but for the guard dropping on their last tick only
        endDrops += int'(outerMatches(s) && !eh[last] && eh[s] && eh[s+1] && eh[s+2]);
      end
      // The stimulus has such attempts
      if (endDrops == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
