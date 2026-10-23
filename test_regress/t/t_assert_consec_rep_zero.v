// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The empty match of a zero-minimum consecutive repetition next to a cycle delay takes a
// cycle off the delay (IEEE 1800-2023 16.9.2.1), checked tick by tick against a procedural
// model

module t (
    input clk
);

  localparam int CYCLES = 100;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  wire a = crc[0];
  wire x = crc[4] | crc[5];
  wire y = crc[8] | crc[9];
  wire c = crc[12];

  // Sampled values and the assertion failures at each tick
  bit hist_a[CYCLES];
  bit hist_x[CYCLES];
  bit hist_y[CYCLES];
  bit hist_c[CYCLES];
  int fail_unb[CYCLES];
  int fail_unb_x[CYCLES];
  int fail_bounded[CYCLES];
  int fail_fused[CYCLES];
  int fail_lhs[CYCLES];
  int fail_cons_fused[CYCLES];
  int fail_lhs_fused[CYCLES];

  assert property (@(posedge clk) a ##1 y [* 0: $] |-> c)
  else fail_unb[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##1 y [* 0: $] ##1 x |-> c)
  else fail_unb_x[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##1 y [* 0: 2] |-> c)
  else fail_bounded[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##0 y [* 0: 2] |-> c)
  else fail_fused[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##2 (y [* 0: 1] ##1 x) |-> c)
  else fail_lhs[$sampled(cyc)]++;
  assert property (@(posedge clk) a |-> x ##0 y [* 0: 1])
  else fail_cons_fused[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##1 (y [* 0: 1] ##0 x) |-> c)
  else fail_lhs_fused[$sampled(cyc)]++;

  // An antecedent match at 'at' fails there when c is false
  function automatic void expectMatch(ref int exp[CYCLES], input int at);
    if (at < CYCLES && !hist_c[at]) exp[at] = 1;
  endfunction

  always @(posedge clk) begin
    hist_a[cyc] = a;
    hist_x[cyc] = x;
    hist_y[cyc] = y;
    hist_c[cyc] = c;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == CYCLES - 1) begin
      int exp_unb[CYCLES];
      int exp_unb_x[CYCLES];
      int exp_bounded[CYCLES];
      int exp_fused[CYCLES];
      int exp_lhs[CYCLES];
      int exp_cons_fused[CYCLES];
      int exp_lhs_fused[CYCLES];
      int nexp[7];
      for (int s = 0; s < CYCLES - 4; ++s) begin
        if (hist_a[s]) begin
          // The empty match ends at s, a match of k repetitions at s + k
          expectMatch(exp_unb, s);
          expectMatch(exp_bounded, s);
          if (hist_x[s+1]) expectMatch(exp_unb_x, s + 1);
          for (int k = 1; s + k < CYCLES - 1 && hist_y[s+k]; ++k) begin
            expectMatch(exp_unb, s + k);
            if (k <= 2) expectMatch(exp_bounded, s + k);
            if (hist_x[s+k+1]) expectMatch(exp_unb_x, s + k + 1);
          end
          // Fused, the first repetition is at s and there is no empty match
          if (hist_y[s]) begin
            expectMatch(exp_fused, s);
            if (hist_y[s+1]) expectMatch(exp_fused, s + 1);
          end
          if (hist_x[s+2]) expectMatch(exp_lhs, s + 2);
          if (hist_y[s+2] && hist_x[s+3]) expectMatch(exp_lhs, s + 3);
          if (!hist_x[s] || !hist_y[s]) exp_cons_fused[s] = 1;
          if (hist_y[s+1] && hist_x[s+1]) expectMatch(exp_lhs_fused, s + 1);
        end
      end
      nexp = '{default: 0};
      for (int i = 0; i < CYCLES - 4; ++i) begin
        `checkd(fail_unb[i], exp_unb[i]);
        `checkd(fail_unb_x[i], exp_unb_x[i]);
        `checkd(fail_bounded[i], exp_bounded[i]);
        `checkd(fail_fused[i], exp_fused[i]);
        `checkd(fail_lhs[i], exp_lhs[i]);
        `checkd(fail_cons_fused[i], exp_cons_fused[i]);
        `checkd(fail_lhs_fused[i], exp_lhs_fused[i]);
        nexp[0] += exp_unb[i];
        nexp[1] += exp_unb_x[i];
        nexp[2] += exp_bounded[i];
        nexp[3] += exp_fused[i];
        nexp[4] += exp_lhs[i];
        nexp[5] += exp_cons_fused[i];
        nexp[6] += exp_lhs_fused[i];
      end
      // Failing ticks expected from the model, so each check above is exercised
      `checkd(nexp[0], 37);
      `checkd(nexp[1], 29);
      `checkd(nexp[2], 34);
      `checkd(nexp[3], 21);
      `checkd(nexp[4], 24);
      `checkd(nexp[5], 20);
      `checkd(nexp[6], 15);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
