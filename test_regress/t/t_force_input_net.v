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

// An input net port forced in its module may be one net with the wire it connects to
// (IEEE 1800-2023 23.3.3.1, 23.3.3.7)
module force_input_helper (
    input wire [6:0] p,
    input wire take,
    input wire drop
);
  logic [6:0] rhs = 7'h00;
  always @(posedge take) force p = rhs;
  always @(posedge drop) release p;
endmodule

module force_input_dut (
    input wire [6:0] raw,
    input wire en,
    input wire take,
    input wire drop,
    output wire [6:0] seen
);
  wire [6:0] csr;
  assign csr = en ? raw : 7'bz;
  assign seen = csr;
  force_input_helper h (
      .p(csr),
      .take(take),
      .drop(drop)
  );
endmodule

// Forced with a value of unknown high impedance state
module port_rhs_helper (
    input wire [6:0] p,
    input wire [6:0] q
);
  initial begin
    #1 force p = q;
    #2 release p;
  end
endmodule

module mixed_helper (
    input wire [6:0] p
);
  initial begin
    #1 force p = 7'h00;
    #2 release p;
  end
endmodule

module pull_helper (
    input wire [1:0] p
);
  initial begin
    #1 force p = 2'b00;
    #2 release p;
  end
endmodule

module xref_forced (
    input wire [6:0] p
);
endmodule

module plain_dut;
  logic [6:0] x_raw = 7'h11;
  wire [6:0] x;
  assign x = x_raw;
endmodule
bind plain_dut force_input_helper h (
    .p(x),
    .take(1'b0),
    .drop(1'b0)
);

module collapsed_z_helper (
    input wire [6:0] p,
    input bit drive
);
  logic [6:0] rhs;
  always_comb rhs = drive ? 7'h29 : 7'bz;
  initial begin
    #2 force p = rhs;
    #4 release p;
  end
endmodule

module pulled_force_helper (
    input wire [6:0] p,
    input bit take,
    input bit drop
);
  always @(posedge take) force p = 7'h00;
  always @(posedge drop) release p;
endmodule

module sibling_puller (
    inout wire [6:0] p
);
  for (genvar bitno = 0; bitno < 7; ++bitno) begin
    pullup (p[bitno]);
  end
endmodule

module pull_forwarder (
    inout wire [6:0] p
);
  sibling_puller s (.p(p));
endmodule

module bit_puller (
    inout wire p
);
  pullup (p);
endmodule

module selected_pull_force_helper (
    input wire [6:0] p
);
  initial begin
    #2 force p = 7'h00;
    #2 release p;
  end
endmodule

module expression_rhs_helper (
    input wire [6:0] p,
    input bit q
);
  initial begin
    #1 force p = {7{q}};
    #2 release p;
  end
endmodule

module t;
  logic [6:0] raw0 = 7'h11, raw1 = 7'h22;
  logic en0 = 1, en1 = 1, take0 = 0, take1 = 0, drop0 = 0, drop1 = 0;
  wire [6:0] seen0, seen1;
  force_input_dut d0 (
      .raw(raw0),
      .en(en0),
      .take(take0),
      .drop(drop0),
      .seen(seen0)
  );
  force_input_dut d1 (
      .raw(raw1),
      .en(en1),
      .take(take1),
      .drop(drop1),
      .seen(seen1)
  );
  initial begin
    #1;
    `checkh(seen0, 7'h11);
    `checkh(d0.h.p, 7'h11);
    `checkh(seen1, 7'h22);
    d1.h.rhs = 7'h66;
    take0 = 1;
    take1 = 1;
    #1;
    `checkh(seen0, 7'h00);
    `checkh(d0.csr, 7'h00);
    `checkh(d0.h.p, 7'h00);
    `checkh(seen1, 7'h66);
    en0 = 0;
    #1;
    `checkh(d0.csr === 7'bz, 1'b0);
    `checkh(d0.h.p === 7'bz, 1'b0);
    d0.h.rhs = 7'h5a;
    d1.h.rhs = 7'h77;
    #1;
    `checkh(seen0, 7'h5a);
    `checkh(seen1, 7'h77);
    d0.h.rhs = 7'h25;
    raw0 = 7'h33;
    #1;
    `checkh(seen0, 7'h25);
    drop0 = 1;
    #1;
    `checkh(d0.csr === 7'bz, 1'b1);
    `checkh(d0.h.p === 7'bz, 1'b1);
    en0 = 1;
    #1;
    `checkh(seen0, 7'h33);
    `checkh(d0.h.p, 7'h33);
    raw1 = 7'h44;
    release d1.csr;
    #1;
    `checkh(seen1, 7'h44);
    force d0.csr = 7'h0f;
    #1;
    `checkh(d0.h.p, 7'h0f);
    release d0.h.p;
    #1;
    `checkh(d0.csr, 7'h33);
  end

  // A bound instance forces a wire with an ordinary driver
  plain_dut pd ();
  initial begin
    #1;
    force pd.h.p = 7'h5a;
    #1;
    `checkh(pd.x, 7'h5a);
    release pd.h.p;
    #1;
    `checkh(pd.x, 7'h11);
  end

  // Such a port, a port written by another module, a port forced from another module with
  // other than a constant, a port connected to a pulled net, and a port with a connection
  // other than a whole wire in another instance, each stay a port of their own
  wire [6:0] qx, wx, mx;
  assign qx = 7'h21;
  assign mx = 7'h23;
  logic [13:0] mixed_raw = 14'h1234;
  wire [13:0] mixed_wide;
  assign mixed_wide = mixed_raw;
  port_rhs_helper hq (
      .p(qx),
      .q(7'h3c)
  );
  mixed_helper hw (.p(wx));
  assign hw.p = 7'h22;
  logic [6:0] xv = 7'h24;
  logic [6:0] xw_raw = 7'h25;
  wire [6:0] xw;
  assign xw = xw_raw;
  xref_forced hx (.p(xw));
  initial #1 force hx.p = xv;
  wire [1:0] pl;
  pullup (pl[0]);
  pullup (pl[1]);
  pull_helper hp (.p(pl));
  mixed_helper hm0 (.p(mx));
  mixed_helper hm1 (.p(mixed_wide[6:0]));
  initial begin
    #2;
    `checkh(hq.p, 7'h3c);
    `checkh(qx, 7'h3c);
    `checkh(hw.p, 7'h00);
    `checkh(hm0.p, 7'h00);
    `checkh(mx, 7'h23);
    `checkh(hx.p, 7'h24);
    `checkh(xw, 7'h25);
    `checkh(hp.p, 2'b00);
    `checkh(pl, 2'b11);
    #2;
    `checkh(hq.p, 7'h21);
    `checkh(qx, 7'h21);
    `checkh(hm0.p, 7'h23);
    `checkh(hm1.p, 7'h34);
  end

  // Both names of a collapsed input net observe the same forced high impedance.
  bit zdrive = 0;
  logic [6:0] zraw = 7'h06;
  wire [6:0] znet;
  assign znet = zraw;
  collapsed_z_helper hz (.p(znet), .drive(zdrive));
  initial begin
    #3;
    `checkh(hz.rhs === 7'bz, 1'b1);
    `checkh(znet === 7'bz, 1'b1);
    `checkh(hz.p === 7'bz, 1'b1);
    zdrive = 1;
    #1;
    `checkh(znet, 7'h29);
    `checkh(hz.p, 7'h29);
    zraw = 7'h31;
    #3;
    `checkh(znet, 7'h31);
    `checkh(hz.p, 7'h31);
  end

  // A pull from a sibling, including through another port, prevents input collapse.
  bit pull_take = 0, pull_drop = 0, pull_en = 0;
  logic [6:0] pull_raw = 7'h15;
  wire [6:0] pulled;
  assign pulled = pull_en ? pull_raw : 7'bz;
  pulled_force_helper ph (.p(pulled), .take(pull_take), .drop(pull_drop));
  pull_forwarder pf (.p(pulled));
  initial begin
    #1;
    `checkh(pulled, 7'h7f);
    pull_take = 1;
    #1;
    `checkh(ph.p, 7'h00);
    `checkh(pulled, 7'h7f);
    pull_drop = 1;
    #1;
    `checkh(ph.p, 7'h7f);
    pull_en = 1;
    #1;
    `checkh(pulled, 7'h15);
    `checkh(ph.p, 7'h15);
  end

  // A pull through a selected sibling connection keeps the input net separate.
  bit selected_en = 0;
  logic [6:0] selected_raw = 7'h15;
  wire [6:0] selected_pull;
  assign selected_pull = selected_en ? selected_raw : 7'bz;
  bit_puller ps (.p(selected_pull[0]));
  selected_pull_force_helper hs (.p(selected_pull));
  initial begin
    #3;
    `checkh(selected_pull[0], 1'b1);
    `checkh(hs.p[0], 1'b0);
    #2;
    selected_en = 1;
    #1;
    `checkh(selected_pull, 7'h15);
    `checkh(hs.p, 7'h15);
  end

  // A composite RHS keeps its internal-only input-port force behavior.
  bit expr_value = 0;
  logic [6:0] expr_raw = 7'h21;
  wire [6:0] expr_net;
  assign expr_net = expr_raw;
  expression_rhs_helper he (.p(expr_net), .q(expr_value));
  initial begin
    #2;
    `checkh(he.p, 7'h00);
    `checkh(expr_net, 7'h21);
    expr_value = 1;
    #0.5;
    `checkh(he.p, 7'h7f);
    `checkh(expr_net, 7'h21);
    #1.5;
    expr_raw = 7'h35;
    #1;
    `checkh(he.p, 7'h35);
  end

  initial begin
    #20;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
