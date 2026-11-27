// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A written input port drives the variables connected to it that are driven only as nets
// are, here by a stub's outputs of z, as it would nets; with GEN, in a generate block

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface drv_if #(
    parameter int W = 16
) (
    input logic clk,
    input logic rst_n,
    input logic [W-1:0] d,
    input logic v
);
  clocking cb @(posedge clk or negedge rst_n);
    output v, d;
  endclocking
endinterface

module stub (
    output logic v,
    output logic [3:0] md,
    output logic [11:0] pkt
);
  assign v = {$bits(v){1'bz}};
  assign md = {$bits(md){1'bz}};
  assign pkt = {$bits(pkt){1'bz}};
endmodule

module rde (
    input logic clk,
    input logic v,
    input logic [3:0] md,
    input logic [11:0] pkt,
    output logic seen,
    output logic [15:0] got
);
  always_ff @(posedge clk) begin
    seen <= v;
    if (v) got <= {md, pkt};
  end
endmodule

module dut (
    input logic clk,
    input logic rst_n,
    output logic seen,
    output logic [15:0] got
);
  logic v;
  logic [3:0] md;
  logic [11:0] pkt;
`ifdef GEN
  if (1) begin : GEN_RTL
    stub s (.v, .md, .pkt);
    rde r (.clk, .v, .md, .pkt, .seen, .got);
  end
`else
  stub s (.v, .md, .pkt);
  rde r (.clk, .v, .md, .pkt, .seen, .got);
`endif
endmodule

module h;
`ifdef GEN
  drv_if #(16) di (
      .clk(dut.clk),
      .rst_n(dut.rst_n),
      .v(dut.GEN_RTL.r.v),
      .d({dut.GEN_RTL.r.md, dut.GEN_RTL.r.pkt})
  );
`else
  drv_if #(16) di (
      .clk(dut.clk),
      .rst_n(dut.rst_n),
      .v(dut.r.v),
      .d({dut.r.md, dut.r.pkt})
  );
`endif
  initial begin
    @(di.cb);
    di.cb.v <= 1'b1;
    di.cb.d <= 16'hA5C3;
    @(di.cb);
    di.cb.v <= 1'b0;
  end
endmodule

bind dut h hh ();

module t;
  localparam realtime HALF = 5ns;
  localparam realtime CHECK = 100ns;
  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic seen;
  logic [15:0] got;
  int seen_n = 0;
  initial repeat (40) #HALF clk = ~clk;
  always @(posedge clk) if (seen) seen_n++;
  dut u (
      .clk,
      .rst_n,
      .seen,
      .got
  );
  initial begin
    #CHECK;
    `checkd(seen_n, 1);
    `checkh(got, 16'hA5C3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
