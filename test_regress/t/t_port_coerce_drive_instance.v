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

// The same, the instances spelled differently: from the root, and from their parent

module rde2 (
    input logic clk,
    input logic [6:0] x,
    output logic [6:0] seen
);
  always_ff @(posedge clk) seen <= x;
endmodule

// Two instances of the same module, each driven by its own bind
module dst2 (
    input logic clk,
    output logic [6:0] sa,
    output logic [6:0] sb
);
  wire [6:0] za, zb;
  assign za = 7'bz;
  assign zb = 7'bz;
  rde2 a (
      .clk(clk),
      .x(za),
      .seen(sa)
  );
  rde2 b (
      .clk(clk),
      .x(zb),
      .seen(sb)
  );
endmodule

module drv2a;
  drv_if d (
      .clk($root.t.u2.a.clk),
      .v  ($root.t.u2.a.x)
  );
  initial begin
    @(posedge $root.t.u2.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

module drv2b;
  drv_if d (
      .clk(dst2.b.clk),
      .v  (dst2.b.x)
  );
  initial begin
    @(posedge dst2.b.clk);
    d.cb.v <= 7'h3A;
  end
endmodule

bind dst2 drv2a u_drv2a ();
bind dst2 drv2b u_drv2b ();

// Two instances of one module, each with an instance of the same cell, written from the top
module rde3 (
    input logic clk,
    input logic [6:0] x,
    output logic [6:0] seen
);
  always_ff @(posedge clk) seen <= x;
endmodule

module dst3 (
    input logic clk,
    output logic [6:0] s
);
  wire [6:0] z;
  assign z = 7'bz;
  rde3 a (
      .clk(clk),
      .x(z),
      .seen(s)
  );
endmodule

// The same, one level further down, through a wrapper
module wrap3 (
    input logic clk,
    output logic [6:0] s
);
  dst3 m (
      .clk(clk),
      .s  (s)
  );
endmodule

module drv3a;
  drv_if d (
      .clk(t.uA.a.clk),
      .v  (t.uA.a.x)
  );
  initial begin
    @(posedge t.uA.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

module drv3b;
  drv_if d (
      .clk(t.uB.a.clk),
      .v  (t.uB.a.x)
  );
  initial begin
    @(posedge t.uB.a.clk);
    d.cb.v <= 7'h3A;
  end
endmodule

module drv3c;
  drv_if d (
      .clk(t.w1.m.a.clk),
      .v  (t.w1.m.a.x)
  );
  initial begin
    @(posedge t.w1.m.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

module drv3d;
  drv_if d (
      .clk(t.w2.m.a.clk),
      .v  (t.w2.m.a.x)
  );
  initial begin
    @(posedge t.w2.m.a.clk);
    d.cb.v <= 7'h3A;
  end
endmodule

module t;
  logic clk = 0;
  always #5 clk = ~clk;
  logic [6:0] sa, sb, sa2, sb2, sa3, sb3, sc3, sd3;
  dst u (
      .clk(clk),
      .sa (sa),
      .sb (sb)
  );
  dst2 u2 (
      .clk(clk),
      .sa (sa2),
      .sb (sb2)
  );
  dst3 uA (
      .clk(clk),
      .s  (sa3)
  );
  dst3 uB (
      .clk(clk),
      .s  (sb3)
  );
  wrap3 w1 (
      .clk(clk),
      .s  (sc3)
  );
  wrap3 w2 (
      .clk(clk),
      .s  (sd3)
  );
  drv3a u_drv3a ();
  drv3b u_drv3b ();
  drv3c u_drv3c ();
  drv3d u_drv3d ();
  initial begin
    repeat (4) @(posedge clk);
    `checkh(sa, 7'h65);
    `checkh(sb, 7'h3A);
    `checkh(sa2, 7'h65);
    `checkh(sb2, 7'h3A);
    `checkh(sa3, 7'h65);
    `checkh(sb3, 7'h3A);
    `checkh(sc3, 7'h65);
    `checkh(sd3, 7'h3A);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
