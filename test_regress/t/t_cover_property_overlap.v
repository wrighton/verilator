// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A cover property runs its pass statement once for each successful attempt,
// also for overlapping attempts succeeding on the same tick (IEEE 1800-2023
// 16.14.3), checked against a reference model.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  localparam int CYCLES = 1000;
  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire run = cyc >= 2 && cyc < CYCLES;
  wire a = run && (crc[4] | crc[5]);
  wire b = run && crc[8] && crc[9];
  wire c = run && (crc[12] | crc[13]);
  wire d = run && cyc[3:0] == 0;
  wire r = run && crc[20] && crc[21];

  bit ah[CYCLES + 8], bh[CYCLES + 8], ch[CYCLES + 8], dh[CYCLES + 8], rh[CYCLES + 8];
  always @(posedge clk) begin
    ah[cyc] = a;
    bh[cyc] = b;
    ch[cyc] = c;
    dh[cyc] = d;
    rh[cyc] = r;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  int cov_range = 0;
  cover property (@(posedge clk) a ##[1:3] b) cov_range++;
  int cov_prefix = 0;
  cover property (@(posedge clk) a ##1 c ##[0:2] b) cov_prefix++;
  // Threads of a goto repetition have no fixed offset; attempts never complete together
  int cov_goto = 0;
  cover property (@(posedge clk) d ##1 c [-> 2]) cov_goto++;
  // The abort is in the final condition, but not in the range's clear condition
  int cov_abort = 0;
  cover property (@(posedge clk) sync_reject_on (r) d ##[1:3] b) cov_abort++;

  // A path through an AND combiner has no fixed offset: one attempt, ending at 4 and 5 and
  // matching both on 6, covers once
  wire s3 = cyc == 3, s4 = cyc == 4, s5 = cyc == 5, s6 = cyc == 6;
  int cov_and = 0;
  cover property (@(posedge clk) ((s3 and (s3 ##1 s4)) or (s3 ##2 s5)) ##[1:3] s6) cov_and++;

  // True if b holds in any cycle from s to e
  function automatic bit bAny(int s, int e);
    for (int k = s; k <= e; k++) if (bh[k]) return 1;
    return 0;
  endfunction

  function automatic int refRange();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) n += int'(ah[s] && bAny(s + 1, s + 3));
    return n;
  endfunction
  function automatic int refPrefix();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) n += int'(ah[s] && ch[s+1] && bAny(s + 1, s + 3));
    return n;
  endfunction

  function automatic int refGoto();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) begin
      automatic int seen = 0;
      if (dh[s]) for (int k = s + 1; k < CYCLES + 8 && seen < 2; k++) seen += int'(ch[k]);
      n += int'(seen == 2);
    end
    return n;
  endfunction

  function automatic int refAbort();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) begin
      automatic bit ok = 0;
      if (dh[s])
        for (int k = 0; k <= 3 && !rh[s+k]; k++)
          if (k > 0 && bh[s+k]) begin
            ok = 1;
            break;
          end
      n += int'(ok);
    end
    return n;
  endfunction

  always @(negedge clk) begin
    if (cyc == CYCLES + 8) begin
      `checkd(cov_range, refRange());
      `checkd(cov_prefix, refPrefix());
      `checkd(cov_goto, refGoto());
      `checkd(cov_abort, refAbort());
      `checkd(cov_and, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
