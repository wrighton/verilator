// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

// Constraints on nested selections: a member of an element of an object array reached
// through a member object, a reduction over a queue in a struct member, and members of an
// unpacked struct array in an element of a struct array selected by a random index

class NestLeaf;
  rand bit [6:0] v;
endclass
class NestHolder;
  rand NestLeaf objs[2];
  function new();
    foreach (objs[i]) objs[i] = new;
  endfunction
endclass
class NestTop;
  rand NestHolder h;
  constraint c_v {h.objs[1].v == 7'd5;}
  function new();
    h = new;
  endfunction
endclass

typedef struct {rand int q[$];} queue_t;
class QueueSum;
  rand queue_t s;
  constraint c_sum {s.q.sum() == 9;}
  function new();
    s.q = '{1, 2};
  endfunction
endclass

typedef struct {rand bit [3:0] a;} inner_t;
typedef struct {inner_t sub[2] = '{'{a: 4'd3}, '{a: 4'd5}};} outer_t;
class InnerRead;
  outer_t items[2];
  inner_t expect_sub[2] = '{'{a: 4'd3}, '{a: 4'd5}};
  rand int unsigned idx;
  rand int unsigned j;
  rand bit [3:0] got, got_j;
  constraint c_idx {idx == 4; j == 1;}
  constraint c_val {got == items[idx].sub[1].a; got_j == items[idx].sub[j].a;}
  constraint c_eq {items[idx].sub == expect_sub;}
endclass

module t;
  initial begin
    automatic NestTop top = new;
    automatic QueueSum qsum = new;
    automatic InnerRead inner = new;
    int ok;
    automatic bit failed = 0;
    ok = top.randomize();
    `checkd(ok, 1);
    `checkd(top.h.objs[1].v, 5);
    ok = qsum.randomize();
    `checkd(ok, 1);
    `checkd(qsum.s.q.size(), 2);
    `checkd(qsum.s.q.sum(), 9);
    // An index without an element reads the member initializer
    ok = inner.randomize();
    `checkd(ok, 1);
    `checkd(inner.got, 5);
    `checkd(inner.got_j, 5);
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
