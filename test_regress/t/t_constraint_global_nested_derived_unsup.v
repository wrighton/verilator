// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Objects of classes with array size constraints are solved by the class of the handle, as
// before, as their constraints are not merged, so their arrays' sizes are not left unsolved

class Item;
  rand int unsigned len;
  rand bit [7:0] payload[];
  constraint c_payload {
    len < 16;
    payload.size() == len;
  }
endclass

class ItemLong extends Item;
  constraint c_len {len > 3;}
endclass

class Elem;
  rand int unsigned len;
  constraint c_len {len < 16;}
endclass

class ElemSized extends Elem;
  rand bit [7:0] q[$];
  constraint c_q {q.size() == len;}
endclass

class ElemFixed extends Elem;
  rand bit [7:0] q[$];
  constraint c_q {q.size() == 3;}
endclass

class Holder;
  rand Item h;
  rand int unsigned k;
  constraint c_k {k == h.len;}
endclass

class ElemHolder;
  rand Elem h;
  rand int unsigned k;
  constraint c_k {k == h.len;}
endclass

module t;
  Holder holder;
  ElemHolder elemHolder;
  ItemLong itemLong;
  ElemSized elemSized;
  ElemFixed elemFixed;
  int ok;
  initial begin
    holder = new;
    elemHolder = new;
    itemLong = new;
    elemSized = new;
    elemFixed = new;
    holder.h = itemLong;
    ok = holder.randomize();
    `checkh(ok, 1);
    `checkh(itemLong.payload.size(), itemLong.len);
    elemHolder.h = elemSized;
    ok = elemHolder.randomize();
    `checkh(ok, 1);
    elemHolder.h = elemFixed;
    ok = elemHolder.randomize();
    `checkh(ok, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
