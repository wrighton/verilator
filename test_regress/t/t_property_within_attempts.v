// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Every attempt of an asserted 'within' but the one starting with a fails, at once as a is false
// at its start (IEEE 1800-2023 16.9.10)

module t;
  bit clk = 0;
  always #5 clk = !clk;
  int cyc = 0;
  logic a, b, c, d;
  int passes[int];
  int fails[int];
  // The tick of an action, whether it runs before or after the update of cyc
  int tick = 0;
  always @(negedge clk) tick = cyc;
  always_comb begin
    a = (cyc == 1);
    b = (cyc == 2);
    c = (cyc == 3);
    d = (cyc == 4);
  end
  assert property (@(posedge clk) disable iff (cyc > 8) (b ##1 c) within (a ##3 d))
    ++passes[tick];
  else ++fails[tick];
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      // The attempt starting on cycle 1 matches on cycle 4
      `checkd(passes.size(), 1);
      `checkd(passes[4], 1);
      for (int i = 0; i <= 8; ++i) `checkd(fails[i], int'(i != 1));
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
