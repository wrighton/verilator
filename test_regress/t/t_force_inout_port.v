// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// A force of an inout port forces the net it connects to (IEEE 1800-2023 10.6.2, 23.3.3.7)
module force_harness (
    inout wire [6:0] p,
    input wire take,
    input wire drop
);
  logic [6:0] rhs = 7'h00;
  always @(posedge take) force p = rhs;
  always @(posedge drop) release p;
endmodule

module force_dut (
    input wire [6:0] raw,
    input wire en,
    input wire take,
    input wire drop,
    output wire [6:0] seen
);
  wire [6:0] csr;
  assign csr = en ? raw : 7'bz;
  assign seen = csr;
  force_harness h (
      .p(csr),
      .take(take),
      .drop(drop)
  );
endmodule

module bound_dut (
    input wire [6:0] raw,
    input wire en,
    input wire take,
    input wire drop,
    output wire [6:0] seen
);
  wire [6:0] csr;
  assign csr = en ? raw : 7'bz;
  assign seen = csr;
endmodule
bind bound_dut force_harness h (
    .p(csr),
    .take(take),
    .drop(drop)
);

// A module that drives its inout port, which a force overrides
module driving_harness (
    inout wire [6:0] p,
    input wire en
);
  assign p = en ? 7'h2c : 7'bz;
endmodule

module force_only (
    inout wire [6:0] p
);
endmodule

// A module that forces its inout port and passes it on
module forwarding_harness (
    inout wire [6:0] p,
    input wire en,
    output wire [6:0] y
);
  assign y = en ? p : 7'bz;
  initial begin
    #1 force p = 7'b0z1z0z1;
    #2 release p;
  end
endmodule

// A module processed before the module of the port it reads
module early_observer (
    output logic pattern
);
  initial #2 pattern = t.fw.p === 7'b0z1z0z1;
endmodule

module t;
  // Forced zero is driven, also with the raw driver off; each instance is independent
  logic [6:0] raw0 = 7'h11, raw1 = 7'h22;
  logic en0 = 1, en1 = 1, take0 = 0, take1 = 0, drop0 = 0, drop1 = 0;
  wire [6:0] seen0, seen1;
  force_dut d0 (
      .raw(raw0),
      .en(en0),
      .take(take0),
      .drop(drop0),
      .seen(seen0)
  );
  force_dut d1 (
      .raw(raw1),
      .en(en1),
      .take(take1),
      .drop(drop1),
      .seen(seen1)
  );
  initial begin
    #1;
    `checkh(seen0, 7'h11);
    `checkh(seen1, 7'h22);
    d1.h.rhs = 7'h66;
    take0 = 1;
    take1 = 1;
    #1;
    `checkh(d0.csr, 7'h00);
    `checkh(d0.h.p, 7'h00);
    `checkh(seen1, 7'h66);
    d0.h.rhs = 7'h5a;
    d1.h.rhs = 7'h77;
    #1;
    `checkh(seen0, 7'h5a);
    `checkh(seen1, 7'h77);
    en0 = 0;
    #1;
    `checkh(seen0, 7'h5a);
    `checkh(d0.csr === 7'bz, 1'b0);
    d0.h.rhs = 7'h00;
    #1;
    `checkh(seen0, 7'h00);
    `checkh(d0.csr, 7'h00);
    `checkh(d0.csr === 7'bz, 1'b0);
    `checkh(d0.h.p === 7'bz, 1'b0);
    d0.h.rhs = 7'h25;
    raw0 = 7'h33;
    #1;
    `checkh(seen0, 7'h25);
    // A release restores the current state of the raw driver, here off
    drop0 = 1;
    #1;
    `checkh(d0.csr === 7'bz, 1'b1);
    `checkh(d0.h.p === 7'bz, 1'b1);
    en0 = 1;
    #1;
    `checkh(seen0, 7'h33);
    `checkh(d0.h.p, 7'h33);
    `checkh(seen1, 7'h77);
    // A release through the name of the connected net
    raw1 = 7'h44;
    release d1.csr;
    #1;
    `checkh(seen1, 7'h44);
    `checkh(d1.h.p, 7'h44);
    // A force through the connected net and a release through the port
    force d0.csr = 7'h0f;
    #1;
    `checkh(d0.h.p, 7'h0f);
    raw0 = 7'h55;
    release d0.h.p;
    #1;
    `checkh(d0.csr, 7'h55);
    // Bits forced high impedance, and selects forced and released through either name
    force d0.h.p = 7'bzzz0000;
    en0 = 0;
    #1;
    `checkh(d0.csr === 7'bzzz0000, 1'b1);
    `checkh(d0.h.p === 7'bzzz0000, 1'b1);
    en0 = 1;
    release d0.csr[1:0];
    #1;
    `checkh(d0.csr === 7'bzzz0001, 1'b1);
    force d0.h.p[5:2] = 4'ha;
    #1;
    `checkh(d0.csr === 7'bz101001, 1'b1);
    release d0.csr;
    #1;
    `checkh(d0.csr, 7'h55);
  end

  // The same through a bound instance
  logic [6:0] braw = 7'h19;
  logic ben = 1, btake = 0, bdrop = 0;
  wire [6:0] bseen;
  bound_dut b0 (
      .raw(braw),
      .en(ben),
      .take(btake),
      .drop(bdrop),
      .seen(bseen)
  );
  initial begin
    #1;
    b0.h.rhs = 7'h00;
    btake = 1;
    ben = 0;
    #1;
    `checkh(bseen, 7'h00);
    `checkh(b0.csr === 7'bz, 1'b0);
    braw = 7'h1a;
    bdrop = 1;
    #1;
    `checkh(b0.csr === 7'bz, 1'b1);
    ben = 1;
    #1;
    `checkh(bseen, 7'h1a);
  end

  // A net driven only by the connected ports releases to their drive
  logic hen = 0;
  wire [6:0] port_net;
  driving_harness dh (
      .p(port_net),
      .en(hen)
  );
  force_only fo (.p(port_net));
  initial begin
    #1;
    `checkh(port_net === 7'bz, 1'b1);
    force fo.p = 7'h00;
    #1;
    `checkh(port_net, 7'h00);
    `checkh(dh.p, 7'h00);
    hen = 1;
    #1;
    `checkh(port_net, 7'h00);
    release port_net;
    #1;
    `checkh(port_net, 7'h2c);
    `checkh(fo.p, 7'h2c);
    force port_net = 7'h01;
    hen = 0;
    #1;
    `checkh(fo.p, 7'h01);
    release fo.p;
    #1;
    `checkh(port_net === 7'bz, 1'b1);
    `checkh(fo.p === 7'bz, 1'b1);
  end

  // A wire with a constant driver, and a wire with no driver, connected to forced ports
  wire [6:0] const_net, lone_net;
  assign const_net = 7'h11;
  force_only fc (.p(const_net));
  force_only fl (.p(lone_net));
  initial begin
    #1;
    force fc.p = 7'h5a;
    force fl.p = 7'h55;
    #1;
    `checkh(const_net, 7'h5a);
    `checkh(lone_net, 7'h55);
    release fc.p;
    release fl.p;
    #1;
    `checkh(const_net, 7'h11);
    `checkh(lone_net === 7'bz, 1'b1);
  end

  // A forced port read through another module, and passed on after its release
  logic fen = 1;
  wire [6:0] fnet, fy;
  wire early_pattern;
  assign fnet = fen ? 7'h06 : 7'bz;
  forwarding_harness fw (
      .p(fnet),
      .en(fen),
      .y(fy)
  );
  early_observer eo (.pattern(early_pattern));
  initial begin
    #2;
    `checkh(fnet === 7'b0z1z0z1, 1'b1);
    `checkh(fy === 7'b0z1z0z1, 1'b1);
    #0.1;
    `checkh(early_pattern, 1'b1);
    #1;
    `checkh(fy, 7'h06);
  end

  // An unconnected port with no local driver remains a floating net after release.
  force_only fu (.p());
  initial begin
    #1;
    force fu.p = 7'h2b;
    #1;
    `checkh(fu.p, 7'h2b);
    release fu.p;
    #1;
    `checkh(fu.p === 7'bz, 1'b1);
  end

  initial begin
    #20;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
