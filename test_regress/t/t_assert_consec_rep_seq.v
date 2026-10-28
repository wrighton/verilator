// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Fixed-count consecutive repetition of a multi-cycle sequence: `s[*n]` is
// `s ##1 s ##1 ... ##1 s` (IEEE 1800-2023 16.9.2). Each property is checked against the
// written-out form.

module t (
    input clk
);

  int cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  wire a = crc[0];
  wire b = crc[4];
  wire c = crc[8];

  int fail_rep[1:5];
  int fail_ref[1:5];

  initial begin
    for (int i = 1; i <= 5; ++i) begin
      fail_rep[i] = 0;
      fail_ref[i] = 0;
    end
  end

  // Antecedent
  assert property (@(posedge clk) (a ##1 b) [* 2] |-> c)
  else fail_rep[1] <= fail_rep[1] + 1;
  assert property (@(posedge clk) (a ##1 b ##1 a ##1 b) |-> c)
  else fail_ref[1] <= fail_ref[1] + 1;

  // Consequent
  assert property (@(posedge clk) a |=> (b ##1 !c) [* 3])
  else fail_rep[2] <= fail_rep[2] + 1;
  assert property (@(posedge clk) a |=> b ##1 !c ##1 b ##1 !c ##1 b ##1 !c)
  else fail_ref[2] <= fail_ref[2] + 1;

  // Followed by more of the sequence, without an implication
  assert property (@(posedge clk) (a ##1 !a) [* 2] ##1 b)
  else fail_rep[3] <= fail_rep[3] + 1;
  assert property (@(posedge clk) a ##1 !a ##1 a ##1 !a ##1 b)
  else fail_ref[3] <= fail_ref[3] + 1;

  // Operand with a repetition
  assert property (@(posedge clk) (a [* 2] ##1 b) [* 2] |-> c)
  else fail_rep[4] <= fail_rep[4] + 1;
  assert property (@(posedge clk) (a [* 2] ##1 b ##1 a [* 2] ##1 b) |-> c)
  else fail_ref[4] <= fail_ref[4] + 1;

  // Single repetition
  assert property (@(posedge clk) (a ##2 b) [* 1] |-> c)
  else fail_rep[5] <= fail_rep[5] + 1;
  assert property (@(posedge clk) (a ##2 b) |-> c)
  else fail_ref[5] <= fail_ref[5] + 1;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 99) begin
      for (int i = 1; i <= 5; ++i) begin
        `checkd(fail_rep[i], fail_ref[i]);
        if (fail_ref[i] == 0) `stop;
      end
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
