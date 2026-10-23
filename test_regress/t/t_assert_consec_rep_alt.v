// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A consecutive repetition range followed by a later step fails only when every repetition
// count fails (IEEE 1800-2023 16.9.2), checked tick by tick against a procedural model

module t (
    input clk
);

  localparam int CYCLES = 100;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  wire d = crc[0];
  wire f = crc[4] | crc[5];
  wire g = crc[8];

  // Sampled values and the assertion failures at each tick
  bit hist_d[CYCLES];
  bit hist_f[CYCLES];
  bit hist_g[CYCLES];
  int fail_notf[CYCLES];
  int fail_13[CYCLES];
  int fail_13_fused[CYCLES];
  int fail_02[CYCLES];
  int fail_02_fused[CYCLES];
  int fail_nonover[CYCLES];

  assert property (@(posedge clk) d |-> f [* 2: 3] ##1 !f)
  else fail_notf[$sampled(cyc)]++;
  assert property (@(posedge clk) d |-> f [* 1: 3] ##1 g)
  else fail_13[$sampled(cyc)]++;
  assert property (@(posedge clk) d |-> f [* 1: 3] ##0 g)
  else fail_13_fused[$sampled(cyc)]++;
  assert property (@(posedge clk) d |-> f [* 0: 2] ##1 g)
  else fail_02[$sampled(cyc)]++;
  assert property (@(posedge clk) d |-> f [* 0: 2] ##0 g)
  else fail_02_fused[$sampled(cyc)]++;
  assert property (@(posedge clk) d |=> f [* 2: 4] ##1 g)
  else fail_nonover[$sampled(cyc)]++;

  // Tick at which an attempt of 'f[*lo:hi] ##dly tail' from 's' fails, when its last
  // repetition count fails, or -1 if one matches. 'notF' selects tail !f instead of g.
  function automatic int failTick(int s, int lo, int hi, int dly, bit notF);
    int last = -1;
    for (int k = lo; k <= hi; ++k) begin
      int dead = -1;
      int at = s + k - 1 + dly;
      if (k == 0 && dly == 0) continue;  // Empty match fused with tail does not match
      for (int i = s; i < s + k; ++i) begin
        if (dead < 0 && !hist_f[i]) dead = i;
      end
      if (dead < 0) begin
        if (notF ? !hist_f[at] : hist_g[at]) return -1;
        dead = at;
      end
      if (dead > last) last = dead;
    end
    return last;
  endfunction

  function automatic void expectFail(ref int exp[CYCLES], input int at);
    if (at >= 0) exp[at] = 1;
  endfunction

  always @(posedge clk) begin
    hist_d[cyc] = d;
    hist_f[cyc] = f;
    hist_g[cyc] = g;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == CYCLES - 1) begin
      int exp_notf[CYCLES];
      int exp_13[CYCLES];
      int exp_13_fused[CYCLES];
      int exp_02[CYCLES];
      int exp_02_fused[CYCLES];
      int exp_nonover[CYCLES];
      int nexp[6];
      // Only attempts that complete in the checked window
      for (int s = 0; s < CYCLES - 8; ++s) begin
        if (hist_d[s]) begin
          expectFail(exp_notf, failTick(s, 2, 3, 1, 1));
          expectFail(exp_13, failTick(s, 1, 3, 1, 0));
          expectFail(exp_13_fused, failTick(s, 1, 3, 0, 0));
          expectFail(exp_02, failTick(s, 0, 2, 1, 0));
          expectFail(exp_02_fused, failTick(s, 0, 2, 0, 0));
          expectFail(exp_nonover, failTick(s + 1, 2, 4, 1, 0));
        end
      end
      nexp = '{default: 0};
      for (int i = 0; i < CYCLES - 8; ++i) begin
        `checkd(fail_notf[i], exp_notf[i]);
        `checkd(fail_13[i], exp_13[i]);
        `checkd(fail_13_fused[i], exp_13_fused[i]);
        `checkd(fail_02[i], exp_02[i]);
        `checkd(fail_02_fused[i], exp_02_fused[i]);
        `checkd(fail_nonover[i], exp_nonover[i]);
        nexp[0] += exp_notf[i];
        nexp[1] += exp_13[i];
        nexp[2] += exp_13_fused[i];
        nexp[3] += exp_02[i];
        nexp[4] += exp_02_fused[i];
        nexp[5] += exp_nonover[i];
      end
      // Failing ticks expected from the model, so each check above is exercised
      `checkd(nexp[0], 36);
      `checkd(nexp[1], 11);
      `checkd(nexp[2], 12);
      `checkd(nexp[3], 6);
      `checkd(nexp[4], 17);
      `checkd(nexp[5], 11);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
