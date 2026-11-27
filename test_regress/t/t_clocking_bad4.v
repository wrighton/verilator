// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  logic in, out;
  clocking cb1 @(posedge clk);
    input in;
    output out;
  endclocking

  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  clocking cb2 @(negedge clk);
    input #cyc in;
    input #(-1) out;
  endclocking

  task write(output x);
    x = 1;
  endtask

  always ##1;
  always cb1.out = clk;
  assign cb1.out = clk;
  always write(cb1.out);
  always cb1.out <= @(posedge clk) 1;
  always cb1.out <= #1 1;
  always out <= ##1 1;

  always @(posedge clk) begin
    cb1.in = 1;
    $display(cb1.out);
  end

  logic out3;
  clocking cb3 @(posedge clk);
    output out3;
  endclocking
  always {cb1.out, cb3.out3} <= ##1 2'b11;

  logic in4;
  clocking cb4 @(posedge clk);
    input #1 in4;
  endclocking
  // Only an input clockvar with a #1step skew can be sampled
  assert property (@(posedge clk) cb1.in);
  assert property (@(posedge clk) cb4.in4);
  always @(posedge clk) if ($rose(cb4.in4)) $display(cb4.in4);

  // Clockvars with a non-constant skew are still usable after the error
  logic out5;
  clocking cb5 @(posedge clk);
    output #cyc out5;
  endclocking
  assert property (@(posedge clk) cb2.in);
  always @(cb5) cb5.out5 <= 1;
endmodule
