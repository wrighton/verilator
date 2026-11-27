// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Each attempt of a sequence 'and' matches at the later end of its operands, and fails when
// either operand fails (IEEE 1800-2023 16.9.5), checked per attempt against a model

module t (
    input clk
);
  localparam int END = 300;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];
  wire d = crc[21] | crc[25];
  bit ah[END + 4], bh[END + 4], ch[END + 4], dh[END + 4];

  // A repetition range ending an operand: only the first match of an attempt counts
  int cover_rep = 0, pass_rep = 0, fail_rep = 0, pass_not_rep = 0, fail_not_rep = 0;
  cover property (@(posedge clk) disable iff (cyc > END) (a [*2:3]) and (b [*2])) ++cover_rep;
  assert property (@(posedge clk) disable iff (cyc > END) (a [*2:3]) and (b [*2])) ++pass_rep;
  else ++fail_rep;
  assert property (@(posedge clk) disable iff (cyc > END) not ((a [*2:3]) and (b [*2])))
    ++pass_not_rep;
  else ++fail_not_rep;

  // Operands of different fixed lengths
  int cover_fixed = 0, pass_fixed = 0, fail_fixed = 0;
  cover property (@(posedge clk) disable iff (cyc > END) (a ##1 b) and (c ##2 d)) ++cover_fixed;
  assert property (@(posedge clk) disable iff (cyc > END) (a ##1 b) and (c ##2 d)) ++pass_fixed;
  else ++fail_fixed;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc <= END + 3) begin
      ah[cyc] = a;
      bh[cyc] = b;
      ch[cyc] = c;
      dh[cyc] = d;
    end
    if (cyc == END + 3) begin
      automatic int pr = 0, fr = 0, pf = 0, ff = 0;
      for (int s = 0; s <= END; ++s) begin
        // The repetition row resolves on s, or on s + 1 when a and b hold on s
        if (!(ah[s] && bh[s])) ++fr;
        else if (s + 1 <= END) begin
          if (ah[s+1] && bh[s+1]) ++pr;
          else ++fr;
        end
        // The fixed row fails on its first failed check
        if (!(ah[s] && ch[s])) ++ff;
        else if (s + 1 <= END && !bh[s+1]) ++ff;
        else if (s + 2 <= END) begin
          if (bh[s+1] && dh[s+2]) ++pf;
          else ++ff;
        end
      end
      `checkd(cover_rep, pr);
      `checkd(pass_rep, pr);
      `checkd(fail_rep, fr);
      `checkd(pass_not_rep, fr);
      `checkd(fail_not_rep, pr);
      `checkd(cover_fixed, pf);
      `checkd(pass_fixed, pf);
      `checkd(fail_fixed, ff);
      if (pr == 0 || fr == 0 || pf == 0 || ff == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
