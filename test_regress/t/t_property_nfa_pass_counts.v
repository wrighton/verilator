// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Passes of attempts completing in a cycle where another attempt fails still
// run the pass action (IEEE 1800-2023 16.14.1), checked against a reference model.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire a = crc[0];
  wire b = crc[5];
  wire c = crc[11];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Sampled values one cycle earlier
  bit a1, b1;
  always @(posedge clk) begin
    a1 <= a;
    b1 <= b;
  end

  // Vacuous and nonvacuous passes, without and with a fail action
  int pass_impl = 0, pass_impl_else = 0, ref_impl = 0;
  int fail_impl_else = 0, ref_fail_impl = 0;
  assert property (@(posedge clk) a |-> b ##1 c) pass_impl++;
  assert property (@(posedge clk) a |-> b ##1 c) pass_impl_else++;
  else fail_impl_else++;
  always @(posedge clk) ref_impl += int'(!a) + int'(a1 && b1 && c);
  // Per tick: an implication does not replay the fail action for another attempt failing too
  always @(posedge clk) ref_fail_impl += int'((a && !b) || (a1 && b1 && !c));

  // Followed-by has no vacuous pass
  int pass_followed = 0, ref_followed = 0;
  assert property (@(posedge clk) a #-# b ##1 c) pass_followed++;
  always @(posedge clk) ref_followed += int'(a1 && b1 && c);

  // Sequence property without a fail action
  int pass_seq = 0, ref_seq = 0;
  assert property (@(posedge clk) a ##1 b) pass_seq++;
  always @(posedge clk) ref_seq += int'(a1 && b);

  always @(negedge clk) begin
    if (cyc == 200) begin
      `checkd(pass_impl, ref_impl);
      `checkd(pass_impl_else, ref_impl);
      `checkd(fail_impl_else, ref_fail_impl);
      `checkd(pass_followed, ref_followed);
      `checkd(pass_seq, ref_seq);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
