// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An intersect of fixed-length sequences, a fixed repetition of a boolean among them, passes and
// fails once per attempt (IEEE 1800-2023 16.9.2, 16.9.6), as does an 'or' of them, against a
// model of each attempt

module t (
    input clk
);
  integer cyc = 0;
  reg [63:0] crc = 64'h0f1e_2d3c_4b5a_6978;
  wire a = crc[0] | crc[5];
  wire b = crc[9] | crc[14];
  wire c = crc[20] | crc[27];
  int p0 = 0, f0 = 0, p1 = 0, f1 = 0, p2 = 0, f2 = 0, f3 = 0, f4 = 0, p5 = 0, f5 = 0;
  bit ha[100], hb[100], hc[100];

  assert property (@(posedge clk) (a [* 2]) intersect (b [* 2])) ++p0;
  else ++f0;
  assert property (@(posedge clk) (a ##1 b) intersect (c [* 2])) ++p1;
  else ++f1;
  assert property (@(posedge clk) (a ##1 b) intersect (c ##1 c)) ++p2;
  else ++f2;
  // As an operand of 'or'
  assert property (@(posedge clk) (a [* 2]) or (b ##1 c))
  else ++f3;
  assert property (@(posedge clk) (a [* 2]) or c)
  else ++f4;
  // As both operands of a 'within' of one length
  assert property (@(posedge clk) (!a [* 3]) within (!a [* 3])) ++p5;
  else ++f5;

  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  always @(negedge clk) begin
    if (cyc == 44) begin
      automatic int e0p = 0, e0f = 0, e1p = 0, e1f = 0, e3f = 0, e4f = 0, e5p = 0, e5f = 0;
      // Each attempt resolves by s + 1; count those started by tick 42
      for (int s = 0; s <= 42; ++s) begin
        if (ha[s] && hb[s] && ha[s+1] && hb[s+1]) ++e0p;
        else ++e0f;
        if (ha[s] && hc[s] && hb[s+1] && hc[s+1]) ++e1p;
        else ++e1f;
        if (!(ha[s] && ha[s+1]) && !(hb[s] && hc[s+1])) ++e3f;
        if (!(ha[s] && ha[s+1]) && !hc[s]) ++e4f;
      end
      // An attempt of the 'within' fails on its first tick with a, all resolved by tick 43
      for (int s = 0; s <= 43; ++s) begin
        automatic bit failed = 0;
        for (int k = 0; k <= 2 && !failed; ++k) begin
          if (ha[s+k]) begin
            failed = 1;
            if (s + k <= 43) ++e5f;
          end
        end
        if (!failed && s + 2 <= 43) ++e5p;
      end
      `checkd(p0, e0p);
      `checkd(f0, e0f);
      `checkd(p1, e1p);
      `checkd(f1, e1f);
      `checkd(p2, e1p);
      `checkd(f2, e1f);
      `checkd(f3, e3f);
      `checkd(f4, e4f);
      `checkd(p5, e5p);
      `checkd(f5, e5f);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
