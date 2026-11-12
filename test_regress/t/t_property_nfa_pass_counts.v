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

  // Sampled values one and two cycles earlier
  bit a1, b1, a2;
  always @(posedge clk) begin
    a1 <= a;
    b1 <= b;
    a2 <= a1;
  end

  // Vacuous and nonvacuous passes, without and with a fail action
  int pass_impl = 0, pass_impl_else = 0, ref_impl = 0;
  int fail_impl_else = 0, ref_fail_impl = 0;
  assert property (@(posedge clk) a |-> b ##1 c) pass_impl++;
  else;
  assert property (@(posedge clk) a |-> b ##1 c) pass_impl_else++;
  else fail_impl_else++;
  always @(posedge clk) ref_impl += int'(!a) + int'(a1 && b1 && c);
  // Each failing attempt runs the fail action, also when another attempt fails too
  always @(posedge clk) ref_fail_impl += int'(a && !b) + int'(a1 && b1 && !c);

  // A vacuous pass on a tick where two other attempts fail: each replay of the fail action
  // must not run the pass action again
  int pass_next = 0, ref_next = 0, fail_next = 0, ref_fail_next = 0;
  assert property (@(posedge clk) a |=> b ##1 c) pass_next++;
  else fail_next++;
  always @(posedge clk) ref_next += int'(!a) + int'(a2 && b1 && c);
  always @(posedge clk) ref_fail_next += int'(a1 && !b) + int'(a2 && b1 && !c);

  // Followed-by has no vacuous pass
  int pass_followed = 0, ref_followed = 0;
  assert property (@(posedge clk) a #-# b ##1 c) pass_followed++;
  else;
  always @(posedge clk) ref_followed += int'(a1 && b1 && c);

  // Sequence property without a fail action
  int pass_seq = 0, ref_seq = 0;
  assert property (@(posedge clk) a ##1 b) pass_seq++;
  else;
  always @(posedge clk) ref_seq += int'(a1 && b);

  always @(negedge clk) begin
    if (cyc == 200) begin
      `checkd(pass_impl, ref_impl);
      `checkd(pass_impl_else, ref_impl);
      `checkd(fail_impl_else, ref_fail_impl);
      `checkd(pass_next, ref_next);
      `checkd(fail_next, ref_fail_next);
      `checkd(pass_followed, ref_followed);
      `checkd(pass_seq, ref_seq);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
