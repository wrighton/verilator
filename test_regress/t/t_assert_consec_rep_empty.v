// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A repetition that only matches empty next to a cycle delay (IEEE 1800-2023 16.9.2.1):
// `empty ##n s` is `##(n-1) s` and `s ##n empty` is `s ##(n-1) 1`. Each property is checked
// against an equivalent one.

module t (
    input clk
);

  localparam int NUM_CKS = 1;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  wire a = crc[0];
  wire b = crc[4];
  wire c = crc[8];

  int fail_rep[1:6];
  int fail_ref[1:6];

  initial begin
    for (int i = 1; i <= 6; ++i) begin
      fail_rep[i] = 0;
      fail_ref[i] = 0;
    end
  end

  // OVL assert_change shape: 1'b1 [*0:num_cks-1] ##1 b, with num_cks = 1, is b
  assert property (@(posedge clk) a |=> (1'b1 [* 0:NUM_CKS - 1] ##1 b))
  else fail_rep[1] <= fail_rep[1] + 1;
  assert property (@(posedge clk) a |=> b)
  else fail_ref[1] <= fail_ref[1] + 1;

  // Empty left of ##1
  assert property (@(posedge clk) a |-> (b [* 0] ##1 c))
  else fail_rep[2] <= fail_rep[2] + 1;
  assert property (@(posedge clk) a |-> c)
  else fail_ref[2] <= fail_ref[2] + 1;

  // Empty left of ##3
  assert property (@(posedge clk) a |-> (b [* 0] ##3 c))
  else fail_rep[3] <= fail_rep[3] + 1;
  assert property (@(posedge clk) a |-> ##2 c)
  else fail_ref[3] <= fail_ref[3] + 1;

  // Empty right of ##1, in an antecedent
  assert property (@(posedge clk) (a ##1 b [* 0: 0]) |=> c)
  else fail_rep[4] <= fail_rep[4] + 1;
  assert property (@(posedge clk) a |=> c)
  else fail_ref[4] <= fail_ref[4] + 1;

  // Empty right of ##2
  assert property (@(posedge clk) (a ##2 b [* 0]) |-> c)
  else fail_rep[5] <= fail_rep[5] + 1;
  assert property (@(posedge clk) (a ##1 1'b1) |-> c)
  else fail_ref[5] <= fail_ref[5] + 1;

  // Empty in the middle of a sequence, without an implication
  assert property (@(posedge clk) a ##1 b [* 0] ##1 c)
  else fail_rep[6] <= fail_rep[6] + 1;
  assert property (@(posedge clk) a ##1 c)
  else fail_ref[6] <= fail_ref[6] + 1;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 99) begin
      for (int i = 1; i <= 6; ++i) begin
        `checkd(fail_rep[i], fail_ref[i]);
        if (fail_ref[i] == 0) `stop;
      end
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
