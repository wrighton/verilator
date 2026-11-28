// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Asserted 'or' forms that keep the merge vertex of their operands, which does not report an
// attempt in which every operand fails (IEEE 1800-2023 16.9.7, 16.12.4), and whose passes are
// not counted per attempt. The checks pin the current counts, and each comment gives the
// counts per attempt.

module t (
    input clk
);
  localparam int END = 200;
  localparam int NPROP = 24;

  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire live = cyc < END - 30;
  wire a = (crc[0] | crc[3]) && live;
  wire b = (crc[5] | crc[9]) && live;
  wire c = (crc[13] | crc[17]) && live;
  wire d = (crc[21] | crc[25]) && live;
  wire e = (crc[29] & crc[33]) && live;
  int passes[NPROP];
  int fails[NPROP];
  // Attempts pass 195 times and fail 6 times
  assert property (@(posedge clk) disable iff (cyc > END) a |-> (##[1:2] b) or (##3 c))
    ++passes[0];
  else ++fails[0];
  // Attempts pass 187 times and fail 14 times
  assert property (@(posedge clk) disable iff (cyc > END) a |-> (b [*1:2]) or (c ##1 a))
    ++passes[1];
  else ++fails[1];
  // Attempts pass 200 times and fail once
  assert property (@(posedge clk) disable iff (cyc > END)
      a |-> (##1 b) or (##2 c) or (##3 a) or (##4 b) or (##5 c))
    ++passes[2];
  else ++fails[2];
  // Known limit: 173 passes and 27 failures, where attempts pass 175 times and fail 26 times
  assert property (@(posedge clk) disable iff (cyc > END) a |-> ((##1 b) or (##2 c)) ##1 a)
    ++passes[3];
  else ++fails[3];
  // Known limit: 61 passes and 34 failures, where attempts pass 61 times and fail 140 times
  assert property (@(posedge clk) disable iff (cyc > END)
      ((a ##1 b) or (b ##1 a)) intersect (c ##1 c))
    ++passes[4];
  else ++fails[4];
  // Known limit: 129 passes and 107 failures, where attempts pass 126 times and fail 75 times
  assert property (@(posedge clk) disable iff (cyc > END) a |-> c throughout ((##1 b) or (##2 b)))
    ++passes[5];
  else ++fails[5];
  // Known limit: 189 passes and 15 failures, where attempts pass 186 times and fail 15 times
  assert property (@(posedge clk) disable iff (cyc > END)
      a |-> ##[1:2] (##1 ((b ##1 c) or (c ##1 b))))
    ++passes[6];
  else ++fails[6];
  // Attempts pass 80 times and fail 121 times
  assert property (@(posedge clk) disable iff (cyc > END)
      ((a ##1 b) or (b ##1 a)) within (c ##3 c))
    ++passes[7];
  else ++fails[7];
  // Attempts pass 42 times and fail 159 times
  assert property (@(posedge clk) disable iff (cyc > END)
      ((a ##1 b) within (c ##3 c)) and (b ##4 c))
    ++passes[8];
  else ++fails[8];
  // Known limit: 141 passes and 45 failures, where attempts pass 156 times and fail 45 times
  assert property (@(posedge clk) disable iff (cyc > END)
      a |-> ##[1:2] ((a ##1 b) within (c ##3 c)))
    ++passes[9];
  else ++fails[9];
  // Attempts pass 26 times and fail 175 times
  assert property (@(posedge clk) disable iff (cyc > END)
      (a ##1 b ##1 a ##1 b ##1 a ##1 b ##1 a ##1 b ##1 a) within (c ##20 c))
    ++passes[10];
  else ++fails[10];
  // Attempts pass 194 times and fail 7 times
  assert property (@(posedge clk) disable iff (cyc > END) (a |-> ##1 b) or (b |-> ##1 c))
    ++passes[11];
  else ++fails[11];
  // Attempts pass 186 times and fail 15 times
  assert property (@(posedge clk) disable iff (cyc > END) (a |-> ##1 b) or (c ##1 a))
    ++passes[12];
  else ++fails[12];
  // Known limit: 201 passes and no failure, where attempts pass 123 times and fail 78 times
  assert property (@(posedge clk) disable iff (cyc > END) (always [0:$] a) or b)
    ++passes[13];
  else ++fails[13];
  // Attempts pass 197 times and fail 4 times
  assert property (@(posedge clk) disable iff (cyc > END) b or (a |-> ##[1:2] c))
    ++passes[14];
  else ++fails[14];
  // Attempts pass 181 times and fail 20 times
  assert property (@(posedge clk) disable iff (cyc > END) c or (a |-> always [0:2] b))
    ++passes[15];
  else ++fails[15];
  // Known limit: 96 passes and 96 failures, where attempts pass 82 times and fail 119 times
  assert property (@(posedge clk) disable iff (cyc > END) not ((a ##1 b) or (a ##[2:3] c)))
    ++passes[16];
  else ++fails[16];
  // Attempts pass 77 times and fail 124 times
  assert property (@(posedge clk) disable iff (cyc > END)
      a |-> (a ##1 b ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b
      ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c) or (b ##1 !a ##1 !c ##1 b
      ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1
      !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c) or (c ##1 !b ##1 !a ##1 c ##1 !b ##1 !a ##1 c
      ##1 !b ##1 !a ##1 c ##1 !b ##1 !a ##1 c ##1 !b ##1 !a ##1 c ##1 !b ##1 !a ##1 c ##1 !b ##1
      !a ##1 c ##1 !b ##1 !a) or (!a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a
      ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1
      !c))
    ++passes[17];
  else ++fails[17];
  // Known limit: 0 passes and no failure, where all 200 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END)
      (a ##1 b ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c
      ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c) or (b ##1 !a ##1 !c ##1 b ##1
      !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c
      ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c) or (c ##1 !b ##1 !a ##1 c ##1 !b ##1 !a ##1 c ##1
      !b ##1 !a ##1 c ##1 !b ##1 !a ##1 c ##1 !b ##1 !a ##1 c ##1 !b ##1 !a ##1 c ##1 !b ##1 !a
      ##1 c ##1 !b ##1 !a) or (!a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1
      b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c))
    ++passes[18];
  else ++fails[18];
  // Known limit: no failure, where attempts fail 30 times. With a pass action or a disable
  // condition, the 'not' is reported as needing default clocking.
  assert property (@(posedge clk) c or not (a ##1 b))
  else ++fails[19];
  // Known limit: no failure, where attempts fail 38 times. With a pass action or a disable
  // condition, the 'not' is reported as needing default clocking.
  assert property (@(posedge clk) c or not (a ##[1:2] b))
  else ++fails[20];
  // Known limit: 150 passes and no failure, where attempts pass 156 times and fail 45 times
  assert property (@(posedge clk) disable iff (cyc > END) d or (accept_on(e) a ##1 b))
    ++passes[21];
  else ++fails[21];
  // Known limit: 172 passes and no failure, where attempts pass 172 times and fail 29 times
  assert property (@(posedge clk) disable iff (cyc > END) d or not (a [*2]))
    ++passes[22];
  else ++fails[22];
  // Attempts pass 188 times and fail 13 times
  assert property (@(posedge clk) disable iff (cyc > END) d or (b |-> (always [0:2] c) or e))
    ++passes[23];
  else ++fails[23];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == END + 2) begin
      `checkd(passes[0], 195);
      `checkd(fails[0], 6);
      `checkd(passes[1], 187);
      `checkd(fails[1], 14);
      `checkd(passes[2], 200);
      `checkd(fails[2], 1);
      `checkd(passes[3], 173);
      `checkd(fails[3], 27);
      `checkd(passes[4], 61);
      `checkd(fails[4], 34);
      `checkd(passes[5], 129);
      `checkd(fails[5], 107);
      `checkd(passes[6], 189);
      `checkd(fails[6], 15);
      `checkd(passes[7], 80);
      `checkd(fails[7], 121);
      `checkd(passes[8], 42);
      `checkd(fails[8], 159);
      `checkd(passes[9], 141);
      `checkd(fails[9], 45);
      `checkd(passes[10], 26);
      `checkd(fails[10], 175);
      `checkd(passes[11], 194);
      `checkd(fails[11], 7);
      `checkd(passes[12], 186);
      `checkd(fails[12], 15);
      `checkd(passes[13], 201);
      `checkd(fails[13], 0);
      `checkd(passes[14], 197);
      `checkd(fails[14], 4);
      `checkd(passes[15], 181);
      `checkd(fails[15], 20);
      `checkd(passes[16], 96);
      `checkd(fails[16], 96);
      `checkd(passes[17], 77);
      `checkd(fails[17], 124);
      `checkd(passes[18], 0);
      `checkd(fails[18], 0);
      `checkd(fails[19], 0);
      `checkd(fails[20], 0);
      `checkd(passes[21], 150);
      `checkd(fails[21], 0);
      `checkd(passes[22], 172);
      `checkd(fails[22], 0);
      `checkd(passes[23], 188);
      `checkd(fails[23], 13);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
