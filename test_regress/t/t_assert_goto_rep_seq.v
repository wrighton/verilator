// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Goto repetition that does not start the sequence, checked tick by tick against a
// procedural model of IEEE 1800-2023 16.9.2

module t (
    input clk
);

  localparam int CYCLES = 100;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  wire a = crc[0];
  wire b = crc[4];
  wire c = crc[8];

  // Sampled values and the assertion failures at each tick
  bit hist_a[CYCLES];
  bit hist_b[CYCLES];
  bit hist_c[CYCLES];
  int fail_delay1[CYCLES];
  int fail_delay2[CYCLES];
  int fail_range[CYCLES];
  int fail_cons[CYCLES];
  int fail_cons_eq[CYCLES];
  int fail_cons_nonover[CYCLES];

  // The first occurrence may be on the tick the repetition starts
  assert property (@(posedge clk) a ##1 b [-> 1] |-> c)
  else fail_delay1[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##1 b [-> 2] |-> c)
  else fail_delay2[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##2 b [-> 1: 2] |-> c)
  else fail_range[$sampled(cyc)]++;
  // A step after the single end of the repetition must be able to fail
  assert property (@(posedge clk) a |-> b [-> 2] ##1 c)
  else fail_cons[$sampled(cyc)]++;
  assert property (@(posedge clk) a |-> b [-> 2: 2] ##1 c)
  else fail_cons_eq[$sampled(cyc)]++;
  assert property (@(posedge clk) a |=> b [-> 1] ##2 c)
  else fail_cons_nonover[$sampled(cyc)]++;

  // Tick of the n'th b at or after 'from', or -1
  function automatic int nthB(int from, int n);
    for (int i = from; i < CYCLES; ++i) begin
      if (hist_b[i] && --n == 0) return i;
    end
    return -1;
  endfunction

  // Mark a failure at 'at' if it is inside the checked window and 'ok' is false
  function automatic void expectFail(ref int exp[CYCLES], input int at, input bit ok);
    if (at >= 0 && at < CYCLES - 1 && !ok) exp[at] = 1;
  endfunction

  always @(posedge clk) begin
    hist_a[cyc] = a;
    hist_b[cyc] = b;
    hist_c[cyc] = c;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == CYCLES - 1) begin
      int exp_delay1[CYCLES];
      int exp_delay2[CYCLES];
      int exp_range[CYCLES];
      int exp_cons[CYCLES];
      int exp_cons_nonover[CYCLES];
      int nexp[5];
      for (int s = 0; s < CYCLES; ++s) begin
        if (hist_a[s]) begin
          int t;
          t = nthB(s + 1, 1);
          expectFail(exp_delay1, t, t >= 0 && hist_c[t]);
          t = nthB(s + 1, 2);
          expectFail(exp_delay2, t, t >= 0 && hist_c[t]);
          for (int n = 1; n <= 2; ++n) begin
            t = nthB(s + 2, n);
            expectFail(exp_range, t, t >= 0 && hist_c[t]);
          end
          t = nthB(s, 2);
          if (t >= 0) expectFail(exp_cons, t + 1, hist_c[t+1]);
          t = nthB(s + 1, 1);
          if (t >= 0) expectFail(exp_cons_nonover, t + 2, hist_c[t+2]);
        end
      end
      nexp = '{default: 0};
      for (int i = 0; i < CYCLES - 1; ++i) begin
        `checkd(fail_delay1[i], exp_delay1[i]);
        `checkd(fail_delay2[i], exp_delay2[i]);
        `checkd(fail_range[i], exp_range[i]);
        `checkd(fail_cons[i], exp_cons[i]);
        `checkd(fail_cons_eq[i], exp_cons[i]);
        `checkd(fail_cons_nonover[i], exp_cons_nonover[i]);
        nexp[0] += exp_delay1[i];
        nexp[1] += exp_delay2[i];
        nexp[2] += exp_range[i];
        nexp[3] += exp_cons[i];
        nexp[4] += exp_cons_nonover[i];
      end
      // Failing ticks expected from the model, so each check above is exercised
      `checkd(nexp[0], 14);
      `checkd(nexp[1], 16);
      `checkd(nexp[2], 20);
      `checkd(nexp[3], 16);
      `checkd(nexp[4], 19);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
