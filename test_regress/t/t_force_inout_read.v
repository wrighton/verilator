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
  initial state = 7'h40;
  always @(posedge clk) state <= p;
endmodule

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
    #1 sample_clk = 1;
    #1;
    `checkh(sampler.state, 7'h01);
    release sampler.p;
    sample_clk = 0;
    #1 sample_clk = 1;
    #1;
    `checkh(sampler.state, 7'h03);
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
