// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A nonconsecutive repetition b[=N] under an abort operator matches as
// b[->N] ##1 !b[*0:$] (IEEE 1800-2023 16.9.2, 16.12.14)
module t (
    input clk
);

  int cyc;
  reg [63:0] crc;
  wire a = crc[0];
  wire b = crc[4] & crc[5];
  wire c = crc[8] & crc[9] & crc[10];

  // Test: accept_on with [=1]
  int pass_r1, fail_r1;
  assert property (@(posedge clk) disable iff (cyc < 2) accept_on (c) (a ##1 b [=1]))
    pass_r1++;
  else fail_r1++;
  int pass_e1, fail_e1;
  assert property (@(posedge clk) disable iff (cyc < 2) accept_on (c) (a ##1 b [->1] ##1 (!b) [*0:$]))
    pass_e1++;
  else fail_e1++;
  // Test: accept_on with [=2]
  int pass_r2, fail_r2;
  assert property (@(posedge clk) disable iff (cyc < 2) accept_on (c) (a ##1 b [=2]))
    pass_r2++;
  else fail_r2++;
  int pass_e2, fail_e2;
  assert property (@(posedge clk) disable iff (cyc < 2) accept_on (c) (a ##1 b [->2] ##1 (!b) [*0:$]))
    pass_e2++;
  else fail_e2++;
  // Test: accept_on with [=3]
  int pass_r3, fail_r3;
  assert property (@(posedge clk) disable iff (cyc < 2) accept_on (c) (a ##1 b [=3]))
    pass_r3++;
  else fail_r3++;
  int pass_e3, fail_e3;
  assert property (@(posedge clk) disable iff (cyc < 2) accept_on (c) (a ##1 b [->3] ##1 (!b) [*0:$]))
    pass_e3++;
  else fail_e3++;
  // Test: reject_on with [=1]
  int pass_r4, fail_r4;
  assert property (@(posedge clk) disable iff (cyc < 2) reject_on (c) (a ##1 b [=1]))
    pass_r4++;
  else fail_r4++;
  int pass_e4, fail_e4;
  assert property (@(posedge clk) disable iff (cyc < 2) reject_on (c) (a ##1 b [->1] ##1 (!b) [*0:$]))
    pass_e4++;
  else fail_e4++;
  // Test: reject_on with [=2]
  int pass_r5, fail_r5;
  assert property (@(posedge clk) disable iff (cyc < 2) reject_on (c) (a ##1 b [=2]))
    pass_r5++;
  else fail_r5++;
  int pass_e5, fail_e5;
  assert property (@(posedge clk) disable iff (cyc < 2) reject_on (c) (a ##1 b [->2] ##1 (!b) [*0:$]))
    pass_e5++;
  else fail_e5++;
  // Test: reject_on with [=3]
  int pass_r6, fail_r6;
  assert property (@(posedge clk) disable iff (cyc < 2) reject_on (c) (a ##1 b [=3]))
    pass_r6++;
  else fail_r6++;
  int pass_e6, fail_e6;
  assert property (@(posedge clk) disable iff (cyc < 2) reject_on (c) (a ##1 b [->3] ##1 (!b) [*0:$]))
    pass_e6++;
  else fail_e6++;
  // Test: sync_accept_on with [=1]
  int pass_r7, fail_r7;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_accept_on (c) (a ##1 b [=1]))
    pass_r7++;
  else fail_r7++;
  int pass_e7, fail_e7;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_accept_on (c) (a ##1 b [->1] ##1 (!b) [*0:$]))
    pass_e7++;
  else fail_e7++;
  // Test: sync_accept_on with [=2]
  int pass_r8, fail_r8;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_accept_on (c) (a ##1 b [=2]))
    pass_r8++;
  else fail_r8++;
  int pass_e8, fail_e8;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_accept_on (c) (a ##1 b [->2] ##1 (!b) [*0:$]))
    pass_e8++;
  else fail_e8++;
  // Test: sync_accept_on with [=3]
  int pass_r9, fail_r9;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_accept_on (c) (a ##1 b [=3]))
    pass_r9++;
  else fail_r9++;
  int pass_e9, fail_e9;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_accept_on (c) (a ##1 b [->3] ##1 (!b) [*0:$]))
    pass_e9++;
  else fail_e9++;
  // Test: sync_reject_on with [=1]
  int pass_r10, fail_r10;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_reject_on (c) (a ##1 b [=1]))
    pass_r10++;
  else fail_r10++;
  int pass_e10, fail_e10;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_reject_on (c) (a ##1 b [->1] ##1 (!b) [*0:$]))
    pass_e10++;
  else fail_e10++;
  // Test: sync_reject_on with [=2]
  int pass_r11, fail_r11;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_reject_on (c) (a ##1 b [=2]))
    pass_r11++;
  else fail_r11++;
  int pass_e11, fail_e11;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_reject_on (c) (a ##1 b [->2] ##1 (!b) [*0:$]))
    pass_e11++;
  else fail_e11++;
  // Test: sync_reject_on with [=3]
  int pass_r12, fail_r12;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_reject_on (c) (a ##1 b [=3]))
    pass_r12++;
  else fail_r12++;
  int pass_e12, fail_e12;
  assert property (@(posedge clk) disable iff (cyc < 2) sync_reject_on (c) (a ##1 b [->3] ##1 (!b) [*0:$]))
    pass_e12++;
  else fail_e12++;
  // Test: [=2] outside the operand of an abort operator in the property
  int pass_r15, fail_r15;
  assert property (@(posedge clk) disable iff (cyc < 2) b [=2] |-> accept_on (c) a)
    pass_r15++;
  else fail_r15++;
  int pass_e15, fail_e15;
  assert property (@(posedge clk) disable iff (cyc < 2)
                   b [->2] ##1 (!b) [*0:$] |-> accept_on (c) a)
    pass_e15++;
  else fail_e15++;
  // Test: cover with accept_on and [=1]
  int pass_r13;
  cover property (@(posedge clk) disable iff (cyc < 2) accept_on (c) (b [=1])) pass_r13++;
  int pass_e13;
  cover property (@(posedge clk) disable iff (cyc < 2) accept_on (c) (b [->1] ##1 (!b) [*0:$])) pass_e13++;
  // Test: cover with reject_on and [=1]
  int pass_r14;
  cover property (@(posedge clk) disable iff (cyc < 2) reject_on (c) (b [=1])) pass_r14++;
  int pass_e14;
  cover property (@(posedge clk) disable iff (cyc < 2) reject_on (c) (b [->1] ##1 (!b) [*0:$])) pass_e14++;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) begin
      crc <= 64'h5aef0c8d_d70a4497;
    end else if (cyc == 199) begin
      `checkd(pass_r1, pass_e1);
      `checkd(fail_r1, fail_e1);
      `checkd(pass_r2, pass_e2);
      `checkd(fail_r2, fail_e2);
      `checkd(pass_r3, pass_e3);
      `checkd(fail_r3, fail_e3);
      `checkd(pass_r4, pass_e4);
      `checkd(fail_r4, fail_e4);
      `checkd(pass_r5, pass_e5);
      `checkd(fail_r5, fail_e5);
      `checkd(pass_r6, pass_e6);
      `checkd(fail_r6, fail_e6);
      `checkd(pass_r7, pass_e7);
      `checkd(fail_r7, fail_e7);
      `checkd(pass_r8, pass_e8);
      `checkd(fail_r8, fail_e8);
      `checkd(pass_r9, pass_e9);
      `checkd(fail_r9, fail_e9);
      `checkd(pass_r10, pass_e10);
      `checkd(fail_r10, fail_e10);
      `checkd(pass_r11, pass_e11);
      `checkd(fail_r11, fail_e11);
      `checkd(pass_r12, pass_e12);
      `checkd(fail_r12, fail_e12);
      `checkd(pass_r13, pass_e13);
      `checkd(pass_r14, pass_e14);
      `checkd(pass_r15, pass_e15);
      `checkd(fail_r15, fail_e15);
      `checkd(pass_r1 > 0, 1'b1);
      `checkd(fail_r4 > 0, 1'b1);
      `checkd(pass_r13 > 0, 1'b1);
      `checkd(fail_r15 > 0, 1'b1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
