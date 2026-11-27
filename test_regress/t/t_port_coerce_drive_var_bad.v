// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A variable with two continuous drivers stays a variable driven twice, also where a written
// input port is connected to it (IEEE 1800-2023 6.5)

interface drv_if (
    input logic clk,
    input logic v
);
  clocking cb @(posedge clk);
    output v;
  endclocking
endinterface

module stub (
    output logic v
);
  assign v = 1'bz;
endmodule

module rde (
    input logic clk,
    input logic v,
    output logic seen
);
  always_ff @(posedge clk) seen <= v;
endmodule

// Two stub outputs on the variable, or with ASSIGN_Z, a stub output and an assignment of z
module dut (
    input logic clk,
    output logic seen
);
  logic v;
  stub s (.v);
`ifdef ASSIGN_Z
  assign v = 1'bz;
`else
  stub s2 (.v);
`endif
  rde r (
      .clk,
      .v,
      .seen
  );
endmodule

module t;
  logic clk = 1'b0;
  logic seen;
  dut u (
      .clk,
      .seen
  );
  drv_if d (
      .clk,
      .v(u.r.v)
  );
  initial begin
    @(d.cb);
    d.cb.v <= 1'b1;
  end
endmodule
