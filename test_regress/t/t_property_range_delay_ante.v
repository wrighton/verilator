// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Every tick of a ranged cycle delay in an antecedent ends a match that starts the
// consequent (IEEE 1800-2023 16.9.2.2, 16.12.7), checked tick by tick against a
// procedural model

module t (
    input clk
);

  localparam int CYCLES = 100;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  wire a = crc[0];
  wire b = crc[4];
  wire c = crc[8];
  wire d = crc[12];

  // Sampled values and the assertion failures at each tick
  bit hist_a[CYCLES];
  bit hist_b[CYCLES];
  bit hist_c[CYCLES];
  bit hist_d[CYCLES];
  int fail_cyc[CYCLES];
  int fail_12[CYCLES];
  int fail_02[CYCLES];
  int fail_nonover[CYCLES];
  int fail_lead[CYCLES];
  int fail_two[CYCLES];

  assert property (@(posedge clk) (cyc % 4 == 0) ##[1:2] cyc[0] |-> cyc == 100)
  else fail_cyc[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##[1:2] b |-> c)
  else fail_12[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##[0:2] b |-> c)
  else fail_02[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##[1:3] b |=> c)
  else fail_nonover[$sampled(cyc)]++;
  assert property (@(posedge clk) ##[1:2] b |-> c)
  else fail_lead[$sampled(cyc)]++;
  assert property (@(posedge clk) a ##[1:2] b ##[1:2] c |-> d)
  else fail_two[$sampled(cyc)]++;

  always @(posedge clk) begin
    hist_a[cyc] = a;
    hist_b[cyc] = b;
    hist_c[cyc] = c;
    hist_d[cyc] = d;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == CYCLES - 1) begin
      int exp_cyc[CYCLES];
      int exp_12[CYCLES];
      int exp_02[CYCLES];
      int exp_nonover[CYCLES];
      int exp_lead[CYCLES];
      int exp_two[CYCLES];
      int nexp[6];
      // Only attempts whose matches all lie in the checked window
      for (int s = 0; s < CYCLES - 6; ++s) begin
        if (s % 4 == 0) begin
          for (int u = s + 1; u <= s + 2; ++u) begin
            if (u % 2 == 1 && u != 100) exp_cyc[u] = 1;
          end
        end
        for (int u = s + 1; u <= s + 2; ++u) begin
          if (hist_b[u] && !hist_c[u]) exp_lead[u] = 1;
        end
        if (hist_a[s]) begin
          for (int u = s; u <= s + 3; ++u) begin
            if (hist_b[u]) begin
              if (u >= s + 1 && u <= s + 2 && !hist_c[u]) exp_12[u] = 1;
              if (u <= s + 2 && !hist_c[u]) exp_02[u] = 1;
              if (u >= s + 1 && !hist_c[u+1]) exp_nonover[u+1] = 1;
              if (u >= s + 1 && u <= s + 2) begin
                for (int v = u + 1; v <= u + 2; ++v) begin
                  if (hist_c[v] && !hist_d[v]) exp_two[v] = 1;
                end
              end
            end
          end
        end
      end
      nexp = '{default: 0};
      for (int i = 0; i < CYCLES - 6; ++i) begin
        `checkd(fail_cyc[i], exp_cyc[i]);
        `checkd(fail_12[i], exp_12[i]);
        `checkd(fail_02[i], exp_02[i]);
        `checkd(fail_nonover[i], exp_nonover[i]);
        `checkd(fail_lead[i], exp_lead[i]);
        `checkd(fail_two[i], exp_two[i]);
        nexp[0] += exp_cyc[i];
        nexp[1] += exp_12[i];
        nexp[2] += exp_02[i];
        nexp[3] += exp_nonover[i];
        nexp[4] += exp_lead[i];
        nexp[5] += exp_two[i];
      end
      // Failing ticks expected from the model, so each check above is exercised
      `checkd(nexp[0], 24);
      `checkd(nexp[1], 14);
      `checkd(nexp[2], 19);
      `checkd(nexp[3], 21);
      `checkd(nexp[4], 20);
      `checkd(nexp[5], 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
