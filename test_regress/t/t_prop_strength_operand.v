// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// weak(sequence_expr) and strong(sequence_expr) as property operands
// (IEEE 1800-2023 16.12.2), each compared with the same assertion without
// the strength where it makes no difference
module t (
  input clk
);
  int unsigned crc = 32'h1;
  logic a, b, c;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[5];
    c <= crc[11];
    if (cyc == 40) $finish;
  end

  int fails_weak = 0, ref_fails_weak = 0;
  assert property (@(posedge clk) a |-> weak (b ##1 c))
  else fails_weak++;
  assert property (@(posedge clk) a |-> b ##1 c)
  else ref_fails_weak++;

  int fails_not = 0, ref_fails_not = 0;
  assert property (@(posedge clk) not weak (a ##1 b))
  else fails_not++;
  assert property (@(posedge clk) not (a ##1 b))
  else ref_fails_not++;

  // A sequence matching on its first tick is the same weak or strong
  int fails_strong = 0, ref_fails_strong = 0;
  assert property (@(posedge clk) a |-> strong (b))
  else fails_strong++;
  assert property (@(posedge clk) a |-> b)
  else ref_fails_strong++;

  // Strength does not change what a cover counts
  int covers = 0, ref_covers = 0;
  cover property (@(posedge clk) strong (a ##1 b) or c) covers++;
  cover property (@(posedge clk) (a ##1 b) or c) ref_covers++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_weak, ref_fails_weak);
    `checkd(fails_not, ref_fails_not);
    `checkd(fails_strong, ref_fails_strong);
    `checkd(covers, ref_covers);
    `checkd(ref_fails_weak, 16);
    `checkd(ref_fails_not, 10);
    `checkd(ref_fails_strong, 14);
    `checkd(ref_covers, 20);
    $write("*-* All Finished *-*\n");
  end
endmodule
