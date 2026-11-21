// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The guard of a throughout must also hold on the last tick of its sequence
// (IEEE 1800-2023 16.9.9), checked against a reference model.

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
  wire f = run && (crc[4] | crc[5]);
  wire g = run && (crc[8] | crc[9]);
  wire h = run && (crc[12] | crc[13]);

  bit fh[CYCLES + 8], gh[CYCLES + 8], hh[CYCLES + 8];
  always @(posedge clk) begin
    fh[cyc] = f;
    gh[cyc] = g;
    hh[cyc] = h;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  int cov_seq = 0;
  cover property (@(posedge clk) f throughout (g ##1 g)) cov_seq++;
  int cov_bool = 0;
  cover property (@(posedge clk) (f throughout g) ##1 h) cov_bool++;
  int cov_prefix = 0;
  cover property (@(posedge clk) (f throughout (g ##1 g)) ##1 h) cov_prefix++;
  int cov_nested = 0;
  cover property (@(posedge clk) f throughout (h throughout (g ##1 g))) cov_nested++;
  // A repetition checks its last tick on a guarded step, with no final condition
  int cov_rep = 0;
  cover property (@(posedge clk) f throughout g [* 2]) cov_rep++;
  int cov_range = 0;
  cover sequence (@(posedge clk) f throughout (g ##[1:2] h)) cov_range++;
  int pass_seq = 0;
  assert property (@(posedge clk) f throughout (g ##1 g)) pass_seq++;
  else $write("");

  // A thread rejected by both its next step and the guard fails once. The final checks are
  // true so that every failure is a step or guard rejection: a failing final check on the
  // same tick as another rejection counts once
  int fail_last = 0;
  assert property (@(posedge clk) f throughout (g ##1 1'b1))
  else fail_last++;
  int fail_bool = 0;
  assert property (@(posedge clk) (f throughout g) ##1 1'b1)
  else fail_bool++;
  int fail_prefix = 0;
  assert property (@(posedge clk) (f throughout (g ##1 g)) ##1 1'b1)
  else fail_prefix++;

  // True if f holds from cycle s for n cycles
  function automatic bit fHolds(int s, int n);
    for (int k = 0; k < n; k++) if (!fh[s+k]) return 0;
    return 1;
  endfunction

  function automatic int refSeq();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) n += int'(fHolds(s, 2) && gh[s] && gh[s+1]);
    return n;
  endfunction
  function automatic int refBool();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) n += int'(fh[s] && gh[s] && hh[s+1]);
    return n;
  endfunction
  function automatic int refPrefix();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) n += int'(fHolds(s, 2) && gh[s] && gh[s+1] && hh[s+2]);
    return n;
  endfunction
  function automatic int refNested();
    int n = 0;
    for (int s = 0; s < CYCLES; s++)
      n += int'(fHolds(s, 2) && hh[s] && hh[s+1] && gh[s] && gh[s+1]);
    return n;
  endfunction
  function automatic int refFailLast();
    int n = 0;
    for (int s = 0; s < CYCLES + 8; s++)
      n += int'(!(fh[s] && gh[s])) + int'(fh[s] && gh[s] && !fh[s+1]);
    return n;
  endfunction
  function automatic int refFailBool();
    int n = 0;
    for (int s = 0; s < CYCLES + 8; s++) n += int'(!(fh[s] && gh[s]));
    return n;
  endfunction
  function automatic int refFailPrefix();
    int n = 0;
    for (int s = 0; s < CYCLES + 8; s++)
      n += int'(!(fh[s] && gh[s])) + int'(fh[s] && gh[s] && !(fh[s+1] && gh[s+1]));
    return n;
  endfunction
  function automatic int refRange();
    int n = 0;
    for (int s = 0; s < CYCLES; s++)
      for (int k = 1; k <= 2; k++) n += int'(fHolds(s, k + 1) && gh[s] && hh[s+k]);
    return n;
  endfunction

  always @(negedge clk) begin
    if (cyc == CYCLES + 8) begin
      `checkd(cov_seq, refSeq());
      `checkd(cov_bool, refBool());
      `checkd(cov_prefix, refPrefix());
      `checkd(cov_nested, refNested());
      `checkd(cov_rep, refSeq());
      `checkd(cov_range, refRange());
      `checkd(pass_seq, refSeq());
      `checkd(fail_last, refFailLast());
      `checkd(fail_bool, refFailBool());
      `checkd(fail_prefix, refFailPrefix());
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
