// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A comparison with null of the object a random index selects from an array of class handles
// is whether the index selects an object; an element out of range reads as null (IEEE
// 1800-2023 7.4.6)

class Item;
  rand bit [6:0] v;
endclass

class Holder;
  rand int k;
  rand int j;
  Item fixed[4];
  Item dyn[];
  Item que[$];
  rand Item rdyn[];
  Item by_key[int];
  Item none[2];
  int offs[2] = '{0, -1};
  int which;
  constraint c_k {k inside {[-1 : 4]};}
  constraint c_sel {
    which == 0 -> fixed[k] != null;
    which == 1 -> fixed[k] == null;
    which == 2 -> dyn[k] != null;
    which == 3 -> que[k] == null;
    which == 4 -> rdyn[k] != null;
    which == 5 -> by_key[k] != null;
    which == 6 -> {none[k] != null; j == 1;}
    which == 7 -> null != fixed[k];
    which == 9 -> fixed[k + offs[1]] != null;
  }
  function new();
    fixed[1] = new;
    fixed[3] = new;
    dyn = new[3];
    dyn[2] = new;
    que.push_back(null);
    que.push_back(dyn[2]);
    rdyn = new[2];
    rdyn[0] = new;
    by_key[-1] = new;
    by_key[4] = new;
  endfunction
endclass

// Every element of an array of null handles, and of an empty queue, compares equal to null
class AllNull;
  rand int idx;
  Item objs[2];
  Item qobjs[$];
endclass

// A key an associative array does not hold selects its default element, here an object
class LiveDefault;
  rand int k;
  Item a[int];
  int which;
  constraint c {
    k inside {[0 : 4]};
    which == 0 -> a[k] == null;
    which == 1 -> a[k] != null;
  }
  function new();
    Item live = new;
    a = '{default: live};
    a[1] = live;
    a[2] = null;
  endfunction
endclass

// An index out of range of a fixed-size array in an inline constraint selects no object
class InlineNull;
  rand int k;
  Item a[4];
  function new();
    a[0] = new;
  endfunction
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic AllNull an = new;
    automatic LiveDefault ld = new;
    automatic InlineNull inl = new;
    automatic int ok;
    repeat (20) begin
      h.which = 0;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k == 1 || h.k == 3, 1'b1);
      h.which = 1;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k == 1 || h.k == 3, 1'b0);
      h.which = 2;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k, 2);
      h.which = 3;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k == 1, 1'b0);
      h.which = 4;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k, 0);
      h.which = 5;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k == -1 || h.k == 4, 1'b1);
      h.which = 7;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k == 1 || h.k == 3, 1'b1);
      h.which = 9;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k == 2 || h.k == 4, 1'b1);
    end
    // No element selected by any index is an object, so this fails
    h.which = 6;
    h.j = 5;
    ok = h.randomize();
    `checkd(ok, 0);
    `checkd(h.j, 5);
    // In an inline constraint too
    h.which = 8;
    ok = h.randomize() with {fixed[k] == null; k > 2;};
    `checkd(ok, 1);
    `checkd(h.k, 4);
    ok = an.randomize() with {objs[idx] == null;};
    `checkd(ok, 1);
    ok = an.randomize() with {qobjs[idx] == null;};
    `checkd(ok, 1);
    ok = an.randomize() with {objs[idx] != null;};
    `checkd(ok, 0);
    repeat (10) begin
      ld.which = 0;
      ok = ld.randomize();
      `checkd(ok, 1);
      `checkd(ld.k, 2);
      ld.which = 1;
      ok = ld.randomize();
      `checkd(ok, 1);
      `checkd(ld.k != 2, 1'b1);
    end
    repeat (20) begin
      ok = inl.randomize() with {
        k inside {[-2 : 6]};
        a[k] != null;
      };
      `checkd(ok, 1);
      `checkd(inl.k, 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
