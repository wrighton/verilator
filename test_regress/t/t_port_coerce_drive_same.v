// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Spellings of one instance's port must not become several drivers of it: each pair of
// bound drivers below writes the same port, once as dst<n>.a.x and once otherwise, so
// neither drives the net, which stays z

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

// Relative to the instance's parent
module rde1 (
    input logic clk,
    input logic [6:0] x,
    output logic [6:0] seen
);
  always_ff @(posedge clk) seen <= x;
endmodule

module dst1 (
    input logic clk,
    output logic [6:0] s
);
  wire [6:0] z;
  assign z = 7'bz;
  rde1 a (
      .clk(clk),
      .x(z),
      .seen(s)
  );
endmodule

module drv1a;
  drv_if d (
      .clk(dst1.a.clk),
      .v  (dst1.a.x)
  );
  initial begin
    @(posedge dst1.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

module drv1b;
  drv_if d (
      .clk(a.clk),
      .v  (a.x)
  );
  initial begin
    @(posedge a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

bind dst1 drv1a u_drv1a ();
bind dst1 drv1b u_drv1b ();

// From the root
module rde2 (
    input logic clk,
    input logic [6:0] x,
    output logic [6:0] seen
);
  always_ff @(posedge clk) seen <= x;
endmodule

module dst2 (
    input logic clk,
    output logic [6:0] s
);
  wire [6:0] z;
  assign z = 7'bz;
  rde2 a (
      .clk(clk),
      .x(z),
      .seen(s)
  );
endmodule

module drv2a;
  drv_if d (
      .clk(dst2.a.clk),
      .v  (dst2.a.x)
  );
  initial begin
    @(posedge dst2.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

module drv2b;
  drv_if d (
      .clk($root.t.u2.a.clk),
      .v  ($root.t.u2.a.x)
  );
  initial begin
    @(posedge $root.t.u2.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

bind dst2 drv2a u_drv2a ();
bind dst2 drv2b u_drv2b ();

// From the top module
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

module drv3a;
  drv_if d (
      .clk(dst3.a.clk),
      .v  (dst3.a.x)
  );
  initial begin
    @(posedge dst3.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

module drv3b;
  drv_if d (
      .clk(t.u3.a.clk),
      .v  (t.u3.a.x)
  );
  initial begin
    @(posedge t.u3.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

bind dst3 drv3a u_drv3a ();
bind dst3 drv3b u_drv3b ();

// By the name of its module, from inside an instance of it
module rde4 (
    input logic clk,
    input logic [6:0] x,
    output logic [6:0] seen
);
  always_ff @(posedge clk) seen <= x;
endmodule

module dst4 (
    input logic clk,
    output logic [6:0] s
);
  wire [6:0] z;
  assign z = 7'bz;
  rde4 a (
      .clk(clk),
      .x(z),
      .seen(s)
  );
endmodule

module drv4a;
  drv_if d (
      .clk(dst4.a.clk),
      .v  (dst4.a.x)
  );
  initial begin
    @(posedge dst4.a.clk);
    d.cb.v <= 7'h65;
  end
endmodule

module drv4b;
  drv_if d (
      .clk(rde4.clk),
      .v  (rde4.x)
  );
  initial begin
    @(posedge rde4.clk);
    d.cb.v <= 7'h65;
  end
endmodule

bind dst4 drv4a u_drv4a ();
bind rde4 drv4b u_drv4b ();

module t;
  logic clk = 0;
  always #5 clk = ~clk;
  logic [6:0] s1, s2, s3, s4;
  dst1 u1 (
      .clk(clk),
      .s  (s1)
  );
  dst2 u2 (
      .clk(clk),
      .s  (s2)
  );
  dst3 u3 (
      .clk(clk),
      .s  (s3)
  );
  dst4 u4 (
      .clk(clk),
      .s  (s4)
  );
  initial begin
    repeat (4) @(posedge clk);
    `checkh(s1, 7'h00);
    `checkh(s2, 7'h00);
    `checkh(s3, 7'h00);
    `checkh(s4, 7'h00);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
