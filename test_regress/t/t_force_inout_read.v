// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0)
// verilog_format: on

module leaf (
    inout wire [6:0] p,
    input wire local_en,
    output wire [6:0] forwarded
);
  assign p = local_en ? 7'b0010zzz : 7'bzzzzzzz;
  assign forwarded = p;
endmodule

module middle (
    inout wire [14:0] bus,
    input wire local_en,
    output wire [6:0] forwarded
);
  leaf child (
      .p(bus[11:5]),
      .local_en(local_en),
      .forwarded(forwarded)
  );
endmodule

module registered_leaf (
    inout wire [6:0] p,
    input bit clk
);
  logic [6:0] state;
  logic [6:0] continuously_sampled;
  assign continuously_sampled = p;
  initial state = 7'h40;
  always @(posedge clk) state <= p;
endmodule

interface read_if;
  wire [6:0] n;
endinterface

module t;
  logic external_en = 1;
  logic external_partial = 0;
  logic local_en = 0;
  wire [14:0] bus;
  wire [6:0] whole = 7'h11;
  assign bus[11:5] = external_en ? (external_partial ? 7'bzzzz000 : 7'h00) : 7'bzzzzzzz;

  leaf good (
      .p(whole),
      .local_en(1'b0),
      .forwarded()
  );
  wire [6:0] forwarded;
  leaf ordinary (
      .p(bus[11:5]),
      .local_en(local_en),
      .forwarded(forwarded)
  );

  wire [8:0] upper;
  wire [8:0] lower;
  assign {upper[8:5], lower[5:3]} =
      external_en ? (external_partial ? 7'bzzzz000 : 7'h00) : 7'bzzzzzzz;
  wire [6:0] concat_forwarded;
  leaf ordinary_concat (
      .p({upper[8:5], lower[5:3]}),
      .local_en(local_en),
      .forwarded(concat_forwarded)
  );

  wire [14:0] nested_bus;
  assign nested_bus[11:5] = external_en ? (external_partial ? 7'bzzzz000 : 7'h00) : 7'bzzzzzzz;
  wire [6:0] nested_forwarded;
  middle nested (
      .bus(nested_bus),
      .local_en(local_en),
      .forwarded(nested_forwarded)
  );

  tri1 [6:0] pulled_high;
  tri0 [6:0] pulled_low;
  wire [6:0] pulled_high_forwarded, pulled_low_forwarded;
  leaf high (
      .p(pulled_high),
      .local_en(1'b0),
      .forwarded(pulled_high_forwarded)
  );
  leaf low (
      .p(pulled_low),
      .local_en(1'b0),
      .forwarded(pulled_low_forwarded)
  );

  bit sample_clk = 0;
  wire [6:0] sampled_net = 7'h03;
  registered_leaf sampler (
      .p(sampled_net),
      .clk(sample_clk)
  );
  initial begin
    #1 force sampler.p = 7'h01;
    #0.5;
    `checkh(sampler.continuously_sampled, 7'h01);
    #0.5 sample_clk = 1;
    #1;
    `checkh(sampler.state, 7'h01);
    release sampler.p;
    sample_clk = 0;
    #1 sample_clk = 1;
    #1;
    `checkh(sampler.state, 7'h03);
    `checkh(sampler.continuously_sampled, 7'h03);
    force sampler.p = 7'bzzzzzzz;
    #1;
    `checkh(sampler.p === 7'bzzzzzzz, 1'b1);
    release sampler.p;
    #1;
    `checkh(sampler.p === 7'bzzzzzzz, 1'b0);
    `checkh(sampler.continuously_sampled, 7'h03);
  end

  // An interface net connection reads the resolved interface net.
  read_if ifc ();
  assign ifc.n = external_en ? 7'h00 : 7'bzzzzzzz;
  wire [6:0] iface_forwarded;
  leaf iface_ordinary (
      .p(ifc.n),
      .local_en(1'b0),
      .forwarded(iface_forwarded)
  );
  initial begin
    #1.5;
    `checkh(iface_forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(iface_forwarded, 7'h00);
    #1;
    `checkh(iface_forwarded === 7'bzzzzzzz, 1'b1);
  end

  // A parent force of a pulled net overrides its pulls only while forced.
  wire [6:0] bit_pulled;
  pullup (bit_pulled[6]);
  pullup (bit_pulled[5]);
  pulldown (bit_pulled[1]);
  pulldown (bit_pulled[0]);
  tri1 [6:0] forced_high;
  tri0 [6:0] forced_low;
  wire [6:0] bit_pulled_forwarded, forced_high_forwarded, forced_low_forwarded;
  leaf bit_pulled_leaf (
      .p(bit_pulled),
      .local_en(1'b0),
      .forwarded(bit_pulled_forwarded)
  );
  leaf forced_high_leaf (
      .p(forced_high),
      .local_en(1'b0),
      .forwarded(forced_high_forwarded)
  );
  leaf forced_low_leaf (
      .p(forced_low),
      .local_en(1'b0),
      .forwarded(forced_low_forwarded)
  );
  initial begin
    #1.5;
    `checkh(bit_pulled_leaf.p === 7'b11zzz00, 1'b1);
    `checkh(bit_pulled_forwarded === 7'b11zzz00, 1'b1);
    `checkh(forced_high_forwarded === 7'h7f, 1'b1);
    `checkh(forced_low_forwarded === 7'h00, 1'b1);
    force bit_pulled = 7'b0z1z0z1;
    force forced_high = 7'bz0z1z0z;
    force forced_low = 7'b1z0z1z0;
    #0.5;
    `checkh(bit_pulled_leaf.p === 7'b0z1z0z1, 1'b1);
    `checkh(bit_pulled_forwarded === 7'b0z1z0z1, 1'b1);
    `checkh(forced_high_forwarded === 7'bz0z1z0z, 1'b1);
    `checkh(forced_low_forwarded === 7'b1z0z1z0, 1'b1);
    release bit_pulled;
    release forced_high;
    release forced_low;
    #0.5;
    `checkh(bit_pulled_leaf.p === 7'b11zzz00, 1'b1);
    `checkh(bit_pulled_forwarded === 7'b11zzz00, 1'b1);
    `checkh(forced_high_forwarded === 7'h7f, 1'b1);
    `checkh(forced_low_forwarded === 7'h00, 1'b1);
    force bit_pulled[5:1] = 5'bz10z1;
    force forced_high[3:2] = 2'bz0;
    #0.5;
    `checkh(bit_pulled_forwarded === 7'b1z10z10, 1'b1);
    `checkh(forced_high_forwarded === 7'b111z011, 1'b1);
    release bit_pulled[5:1];
    release forced_high[3:2];
    #0.5;
    `checkh(bit_pulled_leaf.p === 7'b11zzz00, 1'b1);
    `checkh(bit_pulled_forwarded === 7'b11zzz00, 1'b1);
    `checkh(forced_high_forwarded === 7'h7f, 1'b1);
    `checkh(forced_low_forwarded === 7'h00, 1'b1);
  end

  task automatic check_ordinary(logic [6:0] expected);
    `checkh(ordinary.p, expected);
    `checkh(ordinary.forwarded, expected);
    `checkh(forwarded, expected);
    `checkh(concat_forwarded, expected);
    `checkh(nested_forwarded, expected);
  endtask

  initial begin
    #1;
    force good.p = 7'h12;
    // Externally driven zero is distinct from a floating connection.
    #1;
    `checkh(ordinary.p === 7'bzzzzzzz, 1'b0);
    `checkh(ordinary.forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(concat_forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(nested_forwarded === 7'bzzzzzzz, 1'b0);
    check_ordinary(7'h00);
    `checkh(whole, 7'h12);
    `checkh(pulled_high_forwarded, 7'h7f);
    `checkh(pulled_low_forwarded, 7'h00);
    `checkh(pulled_high_forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(pulled_low_forwarded === 7'bzzzzzzz, 1'b0);

    external_en = 0;
    #1;
    `checkh(ordinary.p === 7'bzzzzzzz, 1'b1);
    `checkh(ordinary.forwarded === 7'bzzzzzzz, 1'b1);
    `checkh(forwarded === 7'bzzzzzzz, 1'b1);
    `checkh(concat_forwarded === 7'bzzzzzzz, 1'b1);
    `checkh(nested_forwarded === 7'bzzzzzzz, 1'b1);

    local_en = 1;
    #1;
    `checkh(ordinary.p === 7'b0010zzz, 1'b1);
    `checkh(ordinary.forwarded === 7'b0010zzz, 1'b1);
    `checkh(forwarded === 7'b0010zzz, 1'b1);
    `checkh(concat_forwarded === 7'b0010zzz, 1'b1);
    `checkh(nested_forwarded === 7'b0010zzz, 1'b1);

    external_partial = 1;
    external_en = 1;
    #1;
    `checkh(ordinary.p === 7'b0010zzz, 1'b0);
    `checkh(ordinary.forwarded === 7'b0010zzz, 1'b0);
    `checkh(forwarded === 7'b0010zzz, 1'b0);
    check_ordinary(7'h10);

    release good.p;
    #1;
    `checkh(whole, 7'h11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
