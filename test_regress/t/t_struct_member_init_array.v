// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Unpacked array members of unpacked structs take their declaration initializers
// (IEEE 1800-2023 7.2.2)

typedef struct {bit [3:0] a = 4'd1; bit [3:0] b;} inner_t;

class Leaf;
endclass

typedef struct {
  byte uniform[4] = '{4{8'd1}};
  bit [4:0] odd[3] = '{5'd17, 5'd18, 5'd19};
  bit [6:0] rev[2:0] = '{7'd70, 7'd71, 7'd72};
  bit [9:0] sparse[5] = '{1: 10'd513, 3: 10'd770, default: 10'd5};
  bit [2:0] grid[2][3] = '{'{3'd1, 3'd2, 3'd3}, '{3'd4, 3'd5, 3'd6}};
  inner_t sub[2] = '{'{a: 4'd3, b: 4'd4}, '{a: 4'd5, b: 4'd6}};
  inner_t kept[2];
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
    `checkh(o.odd[0], 5'd17);
    `checkh(o.odd[2], 5'd19);
    `checkh(o.rev[2], 7'd70);
    `checkh(o.rev[0], 7'd72);
    `checkh(o.sparse[0], 10'd5);
    `checkh(o.sparse[1], 10'd513);
    `checkh(o.sparse[3], 10'd770);
    `checkh(o.sparse[4], 10'd5);
    `checkh(o.grid[0][2], 3'd3);
    `checkh(o.grid[1][0], 3'd4);
    `checkh(o.sub[0].a, 4'd3);
    `checkh(o.sub[1].b, 4'd6);
    `checkh(o.kept[1].a, 4'd1);
    `checkh(o.kept[1].b, 4'd0);
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
    l.sub[1].a = 4'd7;
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
