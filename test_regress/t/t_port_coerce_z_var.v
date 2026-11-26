// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Drives its port from a variable that only ever holds z, so drives nothing
interface pas_if (
    input logic v
);
  logic den_v = {$bits(den_v){1'bz}};
  // verilator lint_off ASSIGNIN
  assign v = den_v;
  // verilator lint_on ASSIGNIN
endinterface

interface drv_if (
    input logic clk,
    input logic v
);
  // verilator lint_off ASSIGNIN
  clocking cb @(posedge clk);
    output v;
  endclocking
  // verilator lint_on ASSIGNIN
endinterface

module leaf (
    input logic clk,
    input logic v,
    output logic seen
);
  always_ff @(posedge clk) seen <= v;
endmodule

module mid (
    input logic clk,
    input logic v,
    output logic seen
);
  leaf l (.*);
endmodule

// The passive interface is on the input of an instance two levels down
module dut_deep (
    input logic clk,
    input logic v,
    output logic seen
);
  mid m (.*);
endmodule

// The passive interface is on the same input
module dut_same (
    input logic clk,
    input logic v,
    output logic seen
);
  always_ff @(posedge clk) seen <= v;
endmodule

module drv_deep;
  drv_if d (
      .clk(dut_deep.clk),
      .v(dut_deep.v)
  );
  pas_if p (.v(dut_deep.m.l.v));
  initial begin
    @(d.cb);
    d.cb.v <= 1'b1;
  end
endmodule

module drv_same;
  drv_if d (
      .clk(dut_same.clk),
      .v(dut_same.v)
  );
  pas_if p (.v(dut_same.v));
  initial begin
    @(d.cb);
    d.cb.v <= 1'b1;
  end
endmodule

bind dut_deep drv_deep u_drv ();
bind dut_same drv_same u_drv ();

// Written only with z, but also pulled, so driven by the pull
module zpu (
    input wire v
);
  // verilator lint_off ASSIGNIN
  assign v = 1'bz;
  // verilator lint_on ASSIGNIN
  pullup (v);
endmodule

module zpd (
    input wire v
);
  // verilator lint_off ASSIGNIN
  assign v = 1'bz;
  // verilator lint_on ASSIGNIN
  pulldown (v);
endmodule

module zt1 (
    input tri1 v
);
  // verilator lint_off ASSIGNIN
  assign v = 1'bz;
  // verilator lint_on ASSIGNIN
endmodule

module zt0 (
    input tri0 v
);
  // verilator lint_off ASSIGNIN
  assign v = 1'bz;
  // verilator lint_on ASSIGNIN
endmodule

interface zv_if;
  logic zv = 1'bz;
endinterface

module t;
  localparam realtime HALF = 5ns;
  logic clk = 1'b0;
  always #HALF clk = ~clk;

  // Test: the active drive reaches the consumer, the passive one drives nothing
  logic seen_deep;
  logic seen_same;
  dut_deep u_deep (
      .clk,
      .v(),
      .seen(seen_deep)
  );
  dut_same u_same (
      .clk,
      .v(),
      .seen(seen_same)
  );
  initial begin
    #(HALF * 10);
    `checkh(seen_deep, 1'b1);
    `checkh(seen_same, 1'b1);
  end

  // Test: a pull of a port written only with z still drives it and its connection
  wire vpu, vpd, vt1, vt0;
  zpu u_pu (vpu);
  zpd u_pd (vpd);
  zt1 u_t1 (vt1);
  zt0 u_t0 (vt0);
  initial begin
    #(HALF * 3);
    `checkh(u_pu.v, 1'b1);
    `checkh(vpu, 1'b1);
    `checkh(u_pd.v, 1'b0);
    `checkh(vpd, 1'b0);
    `checkh(u_t1.v, 1'b1);
    `checkh(vt1, 1'b1);
    `checkh(u_t0.v, 1'b0);
    `checkh(vt0, 1'b0);
  end

  // Test: a variable never written holds its z initial value
  logic nz = 1'bz;
  logic [6:0] nz7 = 7'bz;
  logic [6:0] nz7r = {7{1'bz}};
  logic [6:0] nz7c = {3'bz, {2{2'bz}}};
  // Other reads of such a variable keep it
  logic zx = 1'bz;
  logic xa = 1'b1;
  wire ox = zx ^ xa;
  wire [1:0] op = zx + xa;
  wire oe = zx == xa;
  // Also one that may be written unseen
  logic pz  /*verilator public_flat_rw*/ = 1'bz;
  // A variable written later holds what is written
  logic wz = 1'bz;
  // An interface variable written through a virtual interface holds what is written
  zv_if zi ();
  virtual zv_if vzi = zi;
  initial begin
    #(HALF * 3);
    wz = 1'b1;
    vzi.zv = 1'b1;
    #(HALF * 3);
    `checkh(nz === 1'bz, 1'b1);
    `checkh(nz7 === 7'bz, 1'b1);
    `checkh(nz7r === 7'bz, 1'b1);
    `checkh(nz7c === 7'bz, 1'b1);
    `checkh(pz === 1'bz, 1'b1);
    `checkh(wz, 1'b1);
    `checkh(zi.zv, 1'b1);
  end

  initial begin
    #(HALF * 12);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
