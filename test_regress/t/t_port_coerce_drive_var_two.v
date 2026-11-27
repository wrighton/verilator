// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A variable with two continuous drivers is not taken for a net, so a written input port
// connected to it does not drive it, as without the port (IEEE 1800-2023 6.5 makes the two
// drivers an error, which is not reported here)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

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
  localparam realtime HALF = 5ns;
  localparam realtime CHECK = 100ns;
  logic clk = 1'b0;
  logic seen;
  int seen_n = 0;
  initial repeat (40) #HALF clk = ~clk;
  always @(posedge clk) if (seen === 1'b1) seen_n++;
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
    @(d.cb);
    d.cb.v <= 1'b0;
  end
  initial begin
    #CHECK;
    `checkd(seen_n, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
