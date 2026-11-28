// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A whole property 'always p' holds on an attempt only if p holds at every later tick, which is
// not known before the end of simulation, so its pass statements never run (IEEE 1800-2023
// 16.12.11, 16.14.1). Its failures are compared with the same property without the 'always'.
// Nor does an attempt of an implication into an unbounded always pass unless vacuously, nor one
// of 'always [m:$] p'.
module t (
    input clk
);
  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];

  property p_alw;
    always a;
  endproperty

  int passes[8];
  int fails[8];
  int ref_fails[3];
  int vacuous = 0;  // Attempts of the implications whose antecedent does not hold
  assert property (@(posedge clk) always a) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) always (a ##1 b)) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) p_alw) ++passes[2];
  else ++fails[2];
  assume property (@(posedge clk) always a) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) disable iff (cyc < 5) always a) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) b |-> always a) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) b |=> always [2:$] a) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) always [1:$] a) ++passes[7];
  else ++fails[7];
  assert property (@(posedge clk) a)
  else ++ref_fails[0];
  assert property (@(posedge clk) a ##1 b)
  else ++ref_fails[1];
  assert property (@(posedge clk) disable iff (cyc < 5) a)
  else ++ref_fails[2];

  always @(posedge clk) begin
    if (!b && cyc < 100) ++vacuous;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 100) begin
      for (int i = 0; i < 5; ++i) `checkd(passes[i], 0);
      // Known limit: the attempts pass only vacuously, but a vacuous pass on a tick where another
      // attempt fails is not reported, as the property reports one result per tick
      `checkd(vacuous, 27);
      `checkd(passes[5], 24);
      `checkd(passes[6], 21);
      `checkd(passes[7], 0);
      `checkd(fails[0], ref_fails[0]);
      `checkd(fails[1], ref_fails[1]);
      `checkd(fails[2], ref_fails[0]);
      `checkd(fails[3], ref_fails[0]);
      `checkd(fails[4], ref_fails[2]);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
