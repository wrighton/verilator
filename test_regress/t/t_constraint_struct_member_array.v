// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

// An unpacked array member of an element of a struct array selected by a random index; an
// index without an element reads the member's default

typedef struct {rand bit [7:0] vals[2];} plain_t;
typedef struct {rand bit [7:0] vals[2] = '{8'd3, 8'd4};} init_t;

class Plain;
  rand plain_t items[4];
  rand int unsigned idx;
  int unsigned want_idx = 2;
  bit [7:0] want = 8'd7;
  constraint c_idx {idx == want_idx;}
  constraint c_val {items[idx].vals[1] == want;}
endclass

// A nested dimension with a descending range, and a sparse initializer with a default
typedef struct {
  rand bit [4:0] grid[1:0][3] = '{'{5'd1, 5'd2, 5'd3}, '{5'd4, 5'd5, 5'd6}};
  rand bit [4:0] sparse[4] = '{2: 5'd19, default: 5'd2};
} shaped_t;

class Shaped;
  rand shaped_t items[2];
  rand int unsigned idx;
  rand bit [4:0] g10, g02, s2, s3;
  constraint c_idx {idx == 5;}
  constraint c_val {
    g10 == items[idx].grid[1][0];
    g02 == items[idx].grid[0][2];
    s2 == items[idx].sparse[2];
    s3 == items[idx].sparse[3];
  }
endclass

class Init;
  init_t items[4];
  rand int unsigned idx;
  rand bit [7:0] got;
  constraint c_idx {idx == 6;}
  constraint c_val {got == items[idx].vals[1];}
endclass

module t;
  initial begin
    automatic Plain plain = new;
    automatic Init init = new;
    automatic Shaped shaped = new;
    int ok;
    automatic bit failed = 0;
    ok = plain.randomize();
    `checkd(ok, 1);
    `checkd(plain.idx, 2);
    `checkd(plain.items[2].vals[1], 7);
    // Without an element the member reads as zero
    plain.want_idx = 9;
    plain.want = 8'd0;
    ok = plain.randomize();
    `checkd(ok, 1);
    `checkd(plain.idx, 9);
    plain.want = 8'd7;
    ok = plain.randomize();
    `checkd(ok, 0);
    // Without an element the member reads as its declaration initializer
    ok = init.randomize();
    `checkd(ok, 1);
    `checkd(init.got, 4);
    ok = shaped.randomize();
    `checkd(ok, 1);
    `checkd(shaped.g10, 1);
    `checkd(shaped.g02, 6);
    `checkd(shaped.s2, 19);
    `checkd(shaped.s3, 2);
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
