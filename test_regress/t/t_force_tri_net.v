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

module tri_two (
    input logic [6:0] a,
    input logic [6:0] b,
    input logic ea,
    input logic eb
);
  wire [6:0] n;
  assign n = ea ? a : 7'bz;
  assign n = eb ? b : 7'bz;
endmodule

module tri_child (
    inout wire [6:0] p,
    output wire [6:0] seen
);
  assign seen = p;
endmodule

module tri_upward;
  initial begin
    #1 force t.n5 = 7'h00;
    #2 release t.n5;
  end
endmodule

module tri_upward_z;
  initial begin
    #1 force t.n8 = 7'b101zzzz;
    #2 release t.n8;
  end
endmodule

interface tri_iface_forcer;
  initial begin
    #4 force t.n8 = 7'h00;
    #2 release t.n8;
  end
endinterface

module tri_upward_fn;
  function automatic logic [6:0] flip(input logic [6:0] a);
    return a ^ 7'h7f;
  endfunction
  initial begin
    #1 force t.n11 = flip(7'h70);
    #2 release t.n11;
  end
endmodule

module tri_source;
  logic en = 0;
  wire [6:0] q;
  assign q = en ? 7'h12 : 7'bz;
endmodule

module tri_z_unread;
  logic enabled = 1;
  wire [6:0] n;
  assign n = enabled ? 7'h35 : 7'bz;
endmodule

class tri_class_forcer;
  static task force_n13();
    force t.n13 = 7'b10zz01z;
  endtask
endclass

module tri_upward_src;
  initial #1 force t.n12 = t.s12.q;
endmodule

module tri_pulled_down;
  tri0 n;
  wire n_z = n === 1'bz;
  wire [2:0] p;
  pulldown (p[0]);
  pullup (p[2]);
endmodule

interface tri_strength_if;
  wire [1:0] value;
  assign (weak0, weak1) value = 2'b10;
endinterface

module t;
  // A forced net is driven by the forced value, whatever its drivers (IEEE 1800-2023 10.6.2)
  logic [6:0] raw1 = 7'h11;
  logic [6:0] rhs1 = 7'h00;
  logic en1 = 1;
  wire [6:0] n1;
  assign n1 = en1 ? raw1 : 7'bz;
  initial begin
    #1;
    force n1 = rhs1;
    #1;
    `checkh(n1, 7'h00);
    en1 = 0;
    #1;
    `checkh(n1 === 7'bz, 1'b0);
    `checkh(n1, 7'h00);
    rhs1 = 7'h5a;
    raw1 = 7'h33;
    #1;
    `checkh(n1, 7'h5a);
    release n1;
    #1;
    `checkh(n1 === 7'bz, 1'b1);
    en1 = 1;
    #1;
    `checkh(n1, 7'h33);
    force n1 = 7'b0z1z0z1;
    #1;
    `checkh(n1 === 7'b0z1z0z1, 1'b1);
    release n1[2:0];
    #1;
    `checkh(n1 === 7'b0z1z011, 1'b1);
    force n1[6:4] = 3'b101;
    #1;
    `checkh(n1 === 7'b101z011, 1'b1);
    en1 = 0;
    #1;
    `checkh(n1 === 7'b101zzzz, 1'b1);
    release n1;
    #1;
    `checkh(n1 === 7'bz, 1'b1);
    en1 = 1;
    #1;
    `checkh(n1, 7'h33);
  end

  // Force and release through a hierarchical reference; the other instance is unaffected
  logic [6:0] a2 = 7'h21, b2 = 7'h42, rhs2 = 7'h00;
  logic ea2 = 0, eb2 = 0;
  tri_two u2 (
      .a(a2),
      .b(b2),
      .ea(ea2),
      .eb(eb2)
  );
  tri_two u2b (
      .a(a2),
      .b(b2),
      .ea(ea2),
      .eb(eb2)
  );
  initial begin
    #1;
    `checkh(u2.n === 7'bz, 1'b1);
    force u2.n = rhs2;
    #1;
    `checkh(u2.n, 7'h00);
    `checkh(u2.n === 7'bz, 1'b0);
    `checkh(u2b.n === 7'bz, 1'b1);
    rhs2 = 7'h15;
    eb2 = 1;
    #1;
    `checkh(u2.n, 7'h15);
    `checkh(u2b.n, 7'h42);
    release u2.n;
    #1;
    `checkh(u2.n, 7'h42);
    eb2 = 0;
    #1;
    `checkh(u2.n === 7'bz, 1'b1);
  end

  // A force of a net connected to an inout port is seen through the port
  logic [6:0] raw3 = 7'h0f, rhs3 = 7'h00;
  logic en3 = 1;
  wire [6:0] n3, seen3;
  assign n3 = en3 ? raw3 : 7'bz;
  tri_child c3 (
      .p(n3),
      .seen(seen3)
  );
  initial begin
    #1;
    force n3 = rhs3;
    en3 = 0;
    #1;
    `checkh(seen3, 7'h00);
    `checkh(c3.p, 7'h00);
    `checkh(n3 === 7'bz, 1'b0);
    rhs3 = 7'h6c;
    #1;
    `checkh(seen3, 7'h6c);
    release n3;
    #1;
    `checkh(seen3 === 7'bz, 1'b1);
    `checkh(n3 === 7'bz, 1'b1);
    en3 = 1;
    #1;
    `checkh(seen3, 7'h0f);
  end

  // A forced value read from a tristate net passes on its high impedance
  logic es4 = 0, en4 = 1;
  wire [6:0] src4, n4;
  assign src4 = es4 ? 7'h2b : 7'bz;
  assign n4 = en4 ? 7'h11 : 7'bz;
  initial begin
    #1;
    force n4 = src4;
    #1;
    `checkh(n4 === 7'bz, 1'b1);
    es4 = 1;
    #1;
    `checkh(n4, 7'h2b);
    release n4;
    #1;
    `checkh(n4, 7'h11);
  end

  // A force from a module processed before the forced net's module
  logic en5 = 0;
  wire [6:0] n5;
  assign n5 = en5 ? 7'h7e : 7'bz;
  tri_upward u5 ();
  initial begin
    #2;
    `checkh(n5, 7'h00);
    `checkh(n5 === 7'bz, 1'b0);
    #2;
    `checkh(n5 === 7'bz, 1'b1);
  end

  // A force and release in a task
  logic en6 = 0;
  wire [6:0] n6;
  assign n6 = en6 ? 7'h01 : 7'bz;
  task automatic force_n6(input bit on);
    if (on) force n6 = 7'h12;
    else release n6;
  endtask
  initial begin
    #1;
    force_n6(1);
    #1;
    `checkh(n6, 7'h12);
    force_n6(0);
    #1;
    `checkh(n6 === 7'bz, 1'b1);
  end

  // A release of a net with no driver leaves it high impedance
  wire [6:0] n7;
  initial begin
    #1;
    force n7 = 7'h55;
    #1;
    `checkh(n7, 7'h55);
    `checkh(n7 === 7'bz, 1'b0);
    release n7;
    #1;
    `checkh(n7 === 7'bz, 1'b1);
  end

  // A force of high impedance bits from a module processed first, and from an interface
  logic en8 = 0;
  wire [6:0] n8;
  assign n8 = en8 ? 7'h3c : 7'bz;
  tri_upward_z u8 ();
  tri_iface_forcer i8 ();
  initial begin
    #2;
    `checkh(n8 === 7'b101zzzz, 1'b1);
    #3;
    `checkh(n8, 7'h00);
    `checkh(n8 === 7'bz, 1'b0);
    #2;
    `checkh(n8 === 7'bz, 1'b1);
  end

  // Forces of concatenated selects in a task
  logic en9 = 0;
  wire [6:0] a9, b9;
  assign a9 = en9 ? 7'h06 : 7'bz;
  assign b9 = en9 ? 7'h07 : 7'bz;
  task automatic force_ab9(input bit on);
    if (on) force {a9[6:4], b9[2:0]} = 6'b1zz01z;
    else release {a9[6:4], b9[2:0]};
  endtask
  initial begin
    #1;
    force_ab9(1);
    #1;
    `checkh(a9 === 7'b1zzzzzz, 1'b1);
    `checkh(b9 === 7'bzzzz01z, 1'b1);
    force_ab9(0);
    #1;
    `checkh(a9 === 7'bz, 1'b1);
    `checkh(b9 === 7'bz, 1'b1);
  end

  // A force of high impedance bits of an interface strength net in a task
  tri_strength_if s10 ();
  task automatic force_s10(input bit on);
    if (on) force s10.value = 2'bz1;
    else release s10.value;
  endtask
  initial begin
    #1;
    force_s10(1);
    #1;
    `checkh(s10.value === 2'bz1, 1'b1);
    force_s10(0);
    #1;
    `checkh(s10.value, 2'b10);
  end

  // A force from another module with a value of unknown high impedance state
  logic en11 = 1;
  wire [6:0] n11;
  assign n11 = en11 ? 7'h11 : 7'bz;
  tri_upward_fn u11 ();
  initial begin
    #2;
    `checkh(n11, 7'h0f);
    #2;
    `checkh(n11, 7'h11);
  end

  // A force from another module with a net of another module as its value, which overrides
  // only the value, and a force in a class
  logic en12 = 0;
  wire [6:0] n12;
  assign n12 = en12 ? 7'h11 : 7'bz;
  tri_source s12 ();
  tri_upward_src u12 ();
  logic en13 = 0;
  wire [6:0] n13;
  assign n13 = en13 ? 7'h11 : 7'bz;
  initial begin
    #2;
    `checkh(n12 === 7'bz, 1'b1);
    #2;
    tri_class_forcer::force_n13();
    #1;
    `checkh(n13 === 7'b10zz01z, 1'b1);
  end

  // A hierarchical Z force needs no independent high impedance read of its target.
  tri_z_unread u14 ();
  initial begin
    #1;
    force u14.n = 7'b101zzzz;
    #1;
    `checkh(u14.n, 7'h50);
    release u14.n;
    #1;
    `checkh(u14.n, 7'h35);
  end

  // A pulled-down net reads its pull while not forced, and a forced value while forced, also
  // through a hierarchical reference (IEEE 1800-2023 6.6.5, 10.6.2)
  tri_pulled_down u16 ();
  tri0 n16;
  wire n16_hz = u16.n === 1'bz;
  initial begin
    #1;
    `checkh({n16 === 1'bz, u16.n === 1'bz, u16.n_z, n16_hz}, 4'b0000);
    `checkh({u16.p[2] === 1'bz, u16.p[0] === 1'bz}, 2'b00);
    `checkh({n16, u16.n, u16.p[2], u16.p[0]}, 4'b0010);
    force n16 = 1'b1;
    force u16.n = 1'bz;
    force u16.p[1] = 1'b1;
    force u16.p[0] = 1'bz;
    #1;
    `checkh({n16 === 1'bz, u16.n === 1'bz, u16.n_z, n16_hz}, 4'b0111);
    `checkh({u16.p[2] === 1'bz, u16.p[1] === 1'bz, u16.p[0] === 1'bz}, 3'b001);
    `checkh({n16, u16.p[2], u16.p[1]}, 3'b111);
    release n16;
    release u16.n;
    release u16.p;
    #1;
    `checkh({n16 === 1'bz, u16.n === 1'bz, u16.n_z, n16_hz}, 4'b0000);
    `checkh({u16.p[2] === 1'bz, u16.p[1] === 1'bz, u16.p[0] === 1'bz}, 3'b010);
    `checkh({n16, u16.n, u16.p[2], u16.p[0]}, 4'b0010);
  end

  initial begin
    #20;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
