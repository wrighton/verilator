// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Unpacked array members of unpacked structs take their declaration initializers
// (IEEE 1800-2023 7.2.2)

typedef struct {bit [3:0] a = 4'd1; bit [3:0] b;} inner_t;
typedef struct {bit [3:0] lo; bit [3:0] mid = 4'd7; inner_t in; bit [3:0] hi;} wide_t;

typedef enum logic [2:0] {E0, E1 = 3'd3, E2 = 3'd5} enum_t;
typedef bit [5:0] six_t;
typedef six_t six2_t[2:1];
typedef struct packed {bit [2:0] x; bit [4:0] y;} packed_t;

class Leaf;
endclass

typedef struct {
  byte uniform[4] = '{4{8'd1}};
  byte ieee[4] = '{4{1}};
  // A string literal fills an unpacked array of bytes of its length (IEEE 1800-2023 5.9)
  byte beq[4] = "abcd";
  bit [7:0] beu[0:2] = "xyz";
  // A shorter or longer string literal is left justified (IEEE 1800-2023 5.9)
  byte bup[1:4] = "abcd";
  byte bdn[4:1] = "wxyz";
  byte bsh[0:3] = "ab";
  byte bsl[3:6] = "pq";
  byte bds[5:2] = "mn";
  byte blg[2:3] = "xyz";
  bit [32:0] q33[2] = '{33'h1_0000_0001, 33'h1_0000_0002};
  bit [39:0] q40[2] = '{40'h12_3456_789a, 40'h1};
  logic [62:0] q63[3] = '{default: 63'h4000_0000_0000_0001};
  bit [63:0] q64[3] = '{default: 64'hffff_0000_0000_0001, 1: 64'h8000_0000_0000_0000};
  bit [71:0] w72[2] = '{72'h80_0000_0000_0000_0003, 72'h1};
  real r[2] = '{0.5, -2.25};
  enum_t en[3] = '{E1, E2, E0};
  six_t td[2:1] = '{6'd33, 6'd34};
  six2_t ta = '{6'd35, 6'd36};
  packed_t pk[2] = '{'{x: 3'd1, y: 5'd2}, '{x: 3'd3, y: 5'd4}};
  logic [3:0] lx[2] = '{4'b10x1, 4'h2};
  logic [3:0] sx = 4'b10x1;
  bit [4:0] odd[3] = '{5'd17, 5'd18, 5'd19};
  bit [6:0] rev[2:0] = '{7'd70, 7'd71, 7'd72};
  bit [9:0] sparse[5] = '{1: 10'd513, 3: 10'd770, default: 10'd5};
  bit [4:0] up[1:4] = '{5'd21, 5'd22, 5'd23, 5'd24};
  bit [6:0] down[4:1] = '{default: 7'd65, 2: 7'd66};
  int keyed[2:5] = '{3: 7, default: -1};
  bit [3:0] nz[5:7] = '{4'd1, 4'd2, 4'd3};
  bit [2:0] grid[2][3] = '{'{3'd1, 3'd2, 3'd3}, '{3'd4, 3'd5, 3'd6}};
  bit [2:0] box[1:2][4:3] = '{'{3'd1, 3'd2}, '{3'd3, 3'd4}};
  inner_t sub[2] = '{'{a: 4'd3, b: 4'd4}, '{a: 4'd5, b: 4'd6}};
  inner_t kept[2];
  // Struct values whose members are given by name in another order, with a default, or by
  // position
  wide_t ord[3] = '{'{hi: 4'd1, in: '{b: 4'd3, a: 4'd2}, mid: 4'd4, lo: 4'd5},
                    '{in: '{a: 4'd13, b: 4'd14}, default: 4'd6},
                    '{4'd8, 4'd9, '{4'd10, 4'd11}, 4'd12}};
  wide_t keptw[2];
  bit [3:0] dflt[3] = '{default: 4'd11};
  bit [3:0] scalar = 4'd9;
  bit [3:0] plain[2];
  Leaf objs[2];
} outer_t;

class Holder;
  outer_t one;
  outer_t items[2];
endclass

module t;
  outer_t m;
  outer_t mitems[2];

  task automatic check(outer_t o);
    `checkh(o.uniform[0], 8'd1);
    `checkh(o.uniform[3], 8'd1);
    `checkh(o.ieee[0], 8'd1);
    `checkh(o.ieee[1], 8'd1);
    `checkh(o.ieee[2], 8'd1);
    `checkh(o.ieee[3], 8'd1);
    `checkh(o.beq[0], "a");
    `checkh(o.beq[1], "b");
    `checkh(o.beq[2], "c");
    `checkh(o.beq[3], "d");
    `checkh(o.beu[0], "x");
    `checkh(o.beu[1], "y");
    `checkh(o.beu[2], "z");
    `checkh(o.bup[1], "a");
    `checkh(o.bup[2], "b");
    `checkh(o.bup[3], "c");
    `checkh(o.bup[4], "d");
    `checkh(o.bdn[4], "w");
    `checkh(o.bdn[3], "x");
    `checkh(o.bdn[2], "y");
    `checkh(o.bdn[1], "z");
    `checkh(o.bsh[0], "a");
    `checkh(o.bsh[1], "b");
    `checkh(o.bsh[2], 8'h0);
    `checkh(o.bsh[3], 8'h0);
    `checkh(o.bsl[3], "p");
    `checkh(o.bsl[4], "q");
    `checkh(o.bsl[5], 8'h0);
    `checkh(o.bsl[6], 8'h0);
    `checkh(o.bds[5], "m");
    `checkh(o.bds[4], "n");
    `checkh(o.bds[3], 8'h0);
    `checkh(o.bds[2], 8'h0);
    `checkh(o.blg[2], "x");
    `checkh(o.blg[3], "y");
    `checkh(o.q33[0], 33'h1_0000_0001);
    `checkh(o.q33[1], 33'h1_0000_0002);
    `checkh(o.q40[0], 40'h12_3456_789a);
    `checkh(o.q40[1], 40'h1);
    `checkh(o.q63[0], 63'h4000_0000_0000_0001);
    `checkh(o.q63[1], 63'h4000_0000_0000_0001);
    `checkh(o.q63[2], 63'h4000_0000_0000_0001);
    `checkh(o.q64[0], 64'hffff_0000_0000_0001);
    `checkh(o.q64[1], 64'h8000_0000_0000_0000);
    `checkh(o.q64[2], 64'hffff_0000_0000_0001);
    `checkh(o.w72[0], 72'h80_0000_0000_0000_0003);
    `checkh(o.w72[1], 72'h1);
    `checkr(o.r[0], 0.5);
    `checkr(o.r[1], -2.25);
    `checkh(o.en[0], E1);
    `checkh(o.en[1], E2);
    `checkh(o.en[2], E0);
    `checkh(o.td[2], 6'd33);
    `checkh(o.td[1], 6'd34);
    `checkh(o.ta[2], 6'd35);
    `checkh(o.ta[1], 6'd36);
    `checkh(o.pk[0].x, 3'd1);
    `checkh(o.pk[0].y, 5'd2);
    `checkh(o.pk[1].x, 3'd3);
    `checkh(o.pk[1].y, 5'd4);
    // An X bit takes the same value as in a scalar member's initializer
    `checkh(o.lx[0], o.sx);
    `checkh(o.lx[1], 4'h2);
    `checkh(o.odd[0], 5'd17);
    `checkh(o.odd[2], 5'd19);
    `checkh(o.rev[2], 7'd70);
    `checkh(o.rev[0], 7'd72);
    `checkh(o.sparse[0], 10'd5);
    `checkh(o.sparse[1], 10'd513);
    `checkh(o.sparse[3], 10'd770);
    `checkh(o.sparse[4], 10'd5);
    `checkh(o.up[1], 5'd21);
    `checkh(o.up[4], 5'd24);
    `checkh(o.down[4], 7'd65);
    `checkh(o.down[2], 7'd66);
    `checkh(o.down[1], 7'd65);
    `checkh(o.keyed[2], -1);
    `checkh(o.keyed[3], 7);
    `checkh(o.keyed[5], -1);
    `checkh(o.nz[5], 4'd1);
    `checkh(o.nz[7], 4'd3);
    `checkh(o.grid[0][2], 3'd3);
    `checkh(o.grid[1][0], 3'd4);
    `checkh(o.box[1][4], 3'd1);
    `checkh(o.box[1][3], 3'd2);
    `checkh(o.box[2][4], 3'd3);
    `checkh(o.box[2][3], 3'd4);
    `checkh(o.sub[0].a, 4'd3);
    `checkh(o.sub[1].b, 4'd6);
    `checkh(o.kept[1].a, 4'd1);
    `checkh(o.kept[1].b, 4'd0);
    `checkh(o.ord[0].lo, 4'd5);
    `checkh(o.ord[0].mid, 4'd4);
    `checkh(o.ord[0].in.a, 4'd2);
    `checkh(o.ord[0].in.b, 4'd3);
    `checkh(o.ord[0].hi, 4'd1);
    `checkh(o.ord[1].lo, 4'd6);
    `checkh(o.ord[1].mid, 4'd6);
    `checkh(o.ord[1].in.a, 4'd13);
    `checkh(o.ord[1].in.b, 4'd14);
    `checkh(o.ord[1].hi, 4'd6);
    `checkh(o.ord[2].lo, 4'd8);
    `checkh(o.ord[2].mid, 4'd9);
    `checkh(o.ord[2].in.a, 4'd10);
    `checkh(o.ord[2].in.b, 4'd11);
    `checkh(o.ord[2].hi, 4'd12);
    `checkh(o.keptw[1].lo, 4'd0);
    `checkh(o.keptw[1].mid, 4'd7);
    `checkh(o.keptw[1].in.a, 4'd1);
    `checkh(o.keptw[1].in.b, 4'd0);
    `checkh(o.keptw[1].hi, 4'd0);
    `checkh(o.dflt[0], 4'd11);
    `checkh(o.dflt[2], 4'd11);
    `checkh(o.scalar, 4'd9);
    `checkh(o.plain[1], 4'd0);
    if (o.objs[1] != null) `stop;
  endtask

  // Each call resets its automatic variable from the member initializers again
  task automatic checkLocal();
    outer_t l;
    check(l);
    l.uniform[2] = 8'd5;
    l.beq[1] = 8'd0;
    l.bup[1] = 8'd0;
    l.bsl[5] = 8'd1;
    l.q33[0] = '0;
    l.w72[0] = '0;
    l.r[1] = 0.0;
    l.en[0] = E0;
    l.pk[1].y = 5'd0;
    l.up[4] = 5'd0;
    l.down[2] = 7'd0;
    l.keyed[3] = 0;
    l.box[2][3] = 3'd0;
    l.sub[1].a = 4'd7;
    l.ord[0].mid = 4'd0;
    l.ord[2].in.b = 4'd0;
    l.keptw[0].mid = 4'd0;
    l.objs[0] = new;
  endtask

  initial begin
    automatic Holder h = new;
    check(m);
    check(mitems[1]);
    check(h.one);
    check(h.items[0]);
    check(h.items[1]);
    checkLocal();
    checkLocal();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
