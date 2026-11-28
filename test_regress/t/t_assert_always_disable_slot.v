// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The terms of a disable condition of a whole property 'always p' changing in one time slot
// between two ticks: the attempts started on ticks 0 and 1 are disabled only if the condition
// holds after the slot (IEEE 1800-2023 16.12), and otherwise fail with the attempt started on
// tick 2, where a is false. Each check is the number of attempts that fail.
module t;
  logic clk = 0;
  logic a = 1;
  logic x1 = 0, x2 = 0, r1 = 0, r2 = 0, s1 = 0, s2 = 1;
  int fails[8];
  // Both terms toggle in one slot, and back in the next, so the condition never holds
  assert property (@(posedge clk) disable iff (x1 ^ x2) always a)
  else ++fails[0];
  assert property (@(posedge clk) disable iff (x1 ^ x2) always (a ##1 1'b1))
  else ++fails[1];
  // r1 rises in the slot where s1 rises and s2 falls, whose sampled values are still the old ones
  assert property (@(posedge clk) disable iff (r1 && !$sampled(s1)) always a)
  else ++fails[2];
  assert property (@(posedge clk) disable iff (r1 && !$sampled(s1)) always (a ##1 1'b1))
  else ++fails[3];
  assert property (@(posedge clk) disable iff (r1 && $sampled(s2)) always a)
  else ++fails[4];
  assert property (@(posedge clk) disable iff (r1 && $sampled(s2)) always (a ##1 1'b1))
  else ++fails[5];
  // r2 rises in that slot too, assigned after s1
  assert property (@(posedge clk) disable iff (r2 && !$sampled(s1)) always a)
  else ++fails[6];
  assert property (@(posedge clk) disable iff (r2 && !$sampled(s1)) always (a ##1 1'b1))
  else ++fails[7];

  initial begin
    #5 clk = 1;
    #5 clk = 0;
    #5 clk = 1;
    #2 begin
      x1 = 1;
      x2 = 1;
    end
    #1 begin
      x2 = 0;
      x1 = 0;
    end
    #1 begin
      r1 = 1;
      s1 = 1;
      s2 = 0;
      r2 = 1;
    end
    #1 begin
      r1 = 0;
      r2 = 0;
      clk = 0;
    end
    a = 0;
    #5 clk = 1;
    #5 clk = 0;
    a = 1;
    #5 clk = 1;
    #5 clk = 0;
    `checkd(fails[0], 3);
    `checkd(fails[1], 3);
    `checkd(fails[2], 1);
    `checkd(fails[3], 1);
    `checkd(fails[4], 1);
    `checkd(fails[5], 1);
    `checkd(fails[6], 1);
    `checkd(fails[7], 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
