// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface drv_if (
    input logic clk,
    input logic v
);
  // A port not coerced, as connected to a hierarchical reference
  // verilator lint_off ASSIGNIN
  clocking cb @(posedge clk);
    output v;
  endclocking
  // verilator lint_on ASSIGNIN
endinterface

module dut (
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
  dut u_d (.*);
endmodule

// Drives the input of the instance it is bound into, through a clocking block
module drv;
  drv_if d (
      .clk(dut.clk),
      .v(dut.v)
  );
  initial begin
    @(posedge dut.clk);
    d.cb.v <= 1'b1;
  end
endmodule

bind dut drv u_drv ();

// Drives only z, which drives nothing, written in different ways
module zstub #(
    parameter int KIND = 0
) (
    output logic v
);
  if (KIND == 0) begin : g_bit
    assign v = 1'bz;
  end else if (KIND == 1) begin : g_rep
    assign v = {$bits(v){1'bz}};
  end else if (KIND == 2) begin : g_cat
    assign v = {1'bz};
  end else begin : g_fill
    assign v = 'z;
  end
endmodule

// Output only driven by z, through one and two levels of output ports
module zrelay (
    output logic v
);
  zstub u_s (.v);
endmodule

module zrelay2 (
    output wire v
);
  zrelay u_r (.v);
endmodule

// Bound drivers of separate bits of one net, through chains of different depth
module bdut (
    input logic clk,
    input logic p,
    output logic seen
);
  always_ff @(posedge clk) seen <= p;
endmodule

module bdrv;
  drv_if d (
      .clk(bdut.clk),
      .v(bdut.p)
  );
  initial begin
    @(posedge bdut.clk);
    d.cb.v <= 1'b1;
  end
endmodule

bind bdut bdrv u_bdrv ();

module brelay (
    input logic clk,
    input logic p,
    output logic seen
);
  bdut u_hi (.*);
endmodule

module bmid (
    input logic clk,
    input logic [1:0] p,
    output logic [1:0] seen
);
  bdut u_lo (
      .clk,
      .p(p[0]),
      .seen(seen[0])
  );
  brelay u_r (
      .clk,
      .p(p[1]),
      .seen(seen[1])
  );
endmodule

// Bound drivers of the same bits of one net, at the same and at different depths, whose
// drive is unsupported; only that they build is checked
module sdut (
    input logic clk,
    input logic v,
    output logic seen
);
  always_ff @(posedge clk) seen <= v;
endmodule

module sdrv;
  drv_if d (
      .clk(sdut.clk),
      .v(sdut.v)
  );
  initial begin
    @(posedge sdut.clk);
    d.cb.v <= 1'b1;
  end
endmodule

bind sdut sdrv u_sdrv ();

module smid (
    input logic clk,
    input logic v,
    output logic seen
);
  sdut u_d (.*);
endmodule

// A port connected to a concatenation drives each net in it from its bits
interface cat_if (
    input logic clk,
    input logic [15:0] d
);
  // verilator lint_off ASSIGNIN
  clocking cb @(posedge clk);
    output d;
  endclocking
  // verilator lint_on ASSIGNIN
endinterface

module cdut (
    input logic clk,
    input logic [3:0] md,
    input logic [6:0] pkt,
    input logic [7:0] w,
    output logic [15:0] got
);
  always_ff @(posedge clk) got <= {md, pkt, w[6:2]};
endmodule

module cdrv;
  cat_if c (
      .clk(cdut.clk),
      .d({cdut.md, cdut.pkt, cdut.w[6:2]})
  );
  initial begin
    @(posedge cdut.clk);
    c.cb.d <= 16'ha5c3;
  end
endmodule

bind cdut cdrv u_cdrv ();

// A concatenation with a part that is not a net drives none of it
module kdut (
    input logic clk,
    input logic [3:0] md
);
endmodule

module kdrv;
  cat_if c (
      .clk(kdut.clk),
      .d({kdut.md, 12'h0})
  );
  initial begin
    @(posedge kdut.clk);
    c.cb.d <= 16'ha5c3;
  end
endmodule

bind kdut kdrv u_kdrv ();

module t;
  localparam realtime HALF = 5ns;
  logic clk = 1'b0;
  // Otherwise undriven nets the bound drivers drive, through the ports connected to them
  wire v;
  wire mv;
  logic seen;
  logic mseen;
  wire [1:0] bv;
  logic [1:0] bseen;
  bmid u_b (
      .clk,
      .p(bv),
      .seen(bseen)
  );
  dut u (.*);
  wire zv;
  logic zseen;
  zstub u_zs (.v(zv));
  dut u_z (
      .clk,
      .v(zv),
      .seen(zseen)
  );
  // Other forms of z
  wire [2:0] zkv;
  logic [2:0] zkseen;
  for (genvar k = 1; k <= 3; ++k) begin : g_zk
    zstub #(.KIND(k)) u_zs (.v(zkv[k-1]));
    dut u_z (
        .clk,
        .v(zkv[k-1]),
        .seen(zkseen[k-1])
    );
  end
  wire zrv;
  wire zrv2;
  logic zrseen;
  logic zrseen2;
  zrelay u_zr (.v(zrv));
  dut u_zrd (
      .clk,
      .v(zrv),
      .seen(zrseen)
  );
  zrelay2 u_zr2 (.v(zrv2));
  dut u_zrd2 (
      .clk,
      .v(zrv2),
      .seen(zrseen2)
  );
  wire sw;
  logic [3:0] sseen;
  sdut u_s1 (
      .clk,
      .v(sw),
      .seen(sseen[0])
  );
  sdut u_s2 (
      .clk,
      .v(sw),
      .seen(sseen[1])
  );
  smid u_sm1 (
      .clk,
      .v(sw),
      .seen(sseen[2])
  );
  smid u_sm2 (
      .clk,
      .v(sw),
      .seen(sseen[3])
  );
  mid u_m (
      .clk,
      .v(mv),
      .seen(mseen)
  );
  wire [3:0] cmd;
  wire [6:0] cpkt;
  wire [7:0] cw;
  logic [15:0] cgot;
  assign cmd = {$bits(cmd) {1'bz}};
  assign cpkt = {$bits(cpkt) {1'bz}};
  wire [3:0] kmd;
  kdut u_k (
      .clk,
      .md(kmd)
  );
  cdut u_c (
      .clk,
      .md(cmd),
      .pkt(cpkt),
      .w(cw),
      .got(cgot)
  );
  initial begin
    repeat (8) #HALF clk = ~clk;
    `checkh(seen, 1'b1);
    `checkh(v, 1'b1);
    `checkh(mseen, 1'b1);
    `checkh(mv, 1'b1);
    `checkh(zseen, 1'b1);
    `checkh(zv, 1'b1);
    `checkh(zkseen, 3'b111);
    `checkh(zkv, 3'b111);
    `checkh(zrseen, 1'b1);
    `checkh(zrv, 1'b1);
    `checkh(zrseen2, 1'b1);
    `checkh(zrv2, 1'b1);
    `checkh(bseen, 2'b11);
    `checkh(bv, 2'b11);
    `checkh(cgot, 16'ha5c3);
    `checkh(kmd === 4'ha, 1'b0);
    `checkh(cmd, 4'ha);
    `checkh(cpkt, 7'h2e);
    `checkh(cw[6:2], 5'h03);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
