// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  logic clk = 0;
  int cyc = 0;
  initial forever #5 clk = ~clk;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 3) $finish;
  end

  // A property expression runs in blocks Verilator makes, which are not in the scope: %m in
  // its action, and its default error, at the end of simulation
  assert property (@(posedge clk) 1'b1 s_until (cyc == 100))
  else $display("[%0t] ACTION %m", $time);
  assert property (@(posedge clk) 1'b1 s_until (cyc == 100));

  // A block named in the source is in the scope
  always @(posedge clk) begin : named
    if (cyc == 1) $display("[%0t] NAMED %m", $time);
  end
endmodule
