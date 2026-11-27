// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An implication with an antecedent of a range, under random stimulus, passes or fails once per
// attempt, at the first match whose consequent fails (IEEE 1800-2023 16.12.7, 16.14.1)
module t;
  localparam int CYCLES = 300;

  bit clk = 0;
  always #5 clk = ~clk;

  reg [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  always @(posedge clk) crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];

  int p[2], f[2];
  assert property (@(posedge clk) (a ##[1:2] b) |-> c) ++p[0];
  else ++f[0];
  assert property (@(posedge clk) (a ##[1:2] b) |=> c) ++p[1];
  else ++f[1];

  bit ha[CYCLES], hb[CYCLES], hc[CYCLES];
  int cyc = 0;
  always @(posedge clk) begin
    if (cyc < CYCLES) begin
      ha[cyc] = a;
      hb[cyc] = b;
      hc[cyc] = c;
    end
    cyc <= cyc + 1;
  end

  initial begin
    repeat (CYCLES) @(posedge clk);
    #1;
    for (int i = 0; i < 2; ++i) begin
      automatic int exp_p = 0, exp_f = 0;
      for (int s = 0; s < CYCLES; ++s) begin
        // The tick an attempt resolves on, and whether it passes
        automatic int tick = s;
        automatic bit pass = 1;
        if (ha[s]) begin
          tick = s + 2 + i;
          for (int k = 2; k >= 1; --k) begin
            if (s + k + i < CYCLES && hb[s+k] && !hc[s+k+i]) begin
              pass = 0;
              tick = s + k + i;
            end
          end
        end
        if (tick < CYCLES) begin
          if (pass) ++exp_p;
          else ++exp_f;
        end
      end
      `checkd(p[i], exp_p);
      `checkd(f[i], exp_f);
    end
    `checkd(p[0], 216);
    `checkd(f[0], 83);
    `checkd(p[1], 219);
    `checkd(f[1], 80);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
