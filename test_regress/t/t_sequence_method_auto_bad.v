// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A sequence method instance is evaluated as a concurrent assertion, whose expressions cannot
// reference an automatic variable outside a procedural concurrent assertion (IEEE 1800-2023 16.6)

module t (
    input clk,
    input a,
    input b
);
  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s(x, y);
    @(posedge clk) x ##1 y;
  endsequence
  // verilog_format: on

  task automatic wait_triggered(input logic v);
    wait (s(v, b).triggered);
  endtask
  initial wait_triggered(a);

  function automatic bit is_triggered(input logic v);
    return s(a, v).triggered;
  endfunction
  always @(posedge clk) if (is_triggered(b)) $display("triggered");
endmodule
