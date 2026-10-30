// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Coerced port connected by a hierarchical reference to a non-interface net

interface drv_if (
    input logic clk,
    input logic d
);
  clocking cb @(posedge clk);
    // verilator lint_off ASSIGNIN
    output d;
    // verilator lint_on ASSIGNIN
  endclocking
endinterface

module dut (
    input logic d,
    output logic q
);
  assign q = d;
endmodule

module t (
    input clk,
    output q
);
  dut u (.d(), .q(q));
  drv_if i (.clk(clk), .d(t.u.d));
endmodule
