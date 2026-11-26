// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A written input port of one instance drives its own net, not another instance's

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface drv_if (
    input logic clk,
    input logic [6:0] v
);
  // verilator lint_off ASSIGNIN
  clocking cb @(posedge clk);
    output v;
  endclocking
  // verilator lint_on ASSIGNIN
endinterface

module rde (
    input logic clk,
    input logic [6:0] x,
    output logic [6:0] seen
);
  always_ff @(posedge clk) seen <= x;
endmodule

// Two instances of the same module, each driven by its own bind
module dst (
    input logic clk,
    output logic [6:0] sa,
    output logic [6:0] sb
);
  wire [6:0] za, zb;
  assign za = 7'bz;
  assign zb = 7'bz;
  rde a (
      .clk(clk),
      .x(za),
      .seen(sa)
  );
  rde b (
      .clk(clk),
      .x(zb),
      .seen(sb)
  );
endmodule

module drva;
  drv_if d (
      .clk(dst.a.clk),
      .v  (dst.a.x)
  );
  initial begin
    @(posedge dst.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

module drvb;
  drv_if d (
      .clk(dst.b.clk),
      .v  (dst.b.x)
  );
  initial begin
    @(posedge dst.b.clk);
    d.cb.v <= 7'h3A;
  end
endmodule

bind dst drva u_drva ();
bind dst drvb u_drvb ();

module t;
  logic clk = 0;
  always #5 clk = ~clk;
  logic [6:0] sa, sb;
  dst u (
      .clk(clk),
      .sa (sa),
      .sb (sb)
  );
  initial begin
    repeat (4) @(posedge clk);
    `checkh(sa, 7'h65);
    `checkh(sb, 7'h3A);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
