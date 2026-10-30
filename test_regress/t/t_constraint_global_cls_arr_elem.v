// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An array of rand objects referenced by the constraints of its container: the objects'
// own constraints are solved together with the container's (IEEE 1800-2023 18.5.8), for
// the objects the array holds at each randomize()

class ItemBase;
  rand bit [14:0] u;
  rand bit [6:0] p;
  constraint c_u {u < lim();}
  constraint c_p {p < 7'd10;}  // Overridden
  function bit [14:0] lim();
    return 15'd1000;
  endfunction
endclass

class Cfg;
  bit [6:0] max = 7'd110;
endclass

class Sub;
  rand bit [4:0] x;
  constraint c_x {x != 5'd3;}
endclass

class Item extends ItemBase;
  rand bit [6:0] v;
  rand Sub s;
  rand bit [3:0] arr[3];
  bit [6:0] odds[$];  // Not rand
  bit [6:0] bad[$] = '{7'd17, 7'd19, 7'd21};  // Not rand
  Cfg cfg = new;  // Not rand
  constraint c_odd {v inside {odds};}
  constraint c_cfg {v < cfg.max;}
  constraint c_bad {foreach (bad[i]) v != bad[i];}
  constraint c_empty {}
  constraint c_p {p < 7'd100;}
  constraint c_forms {
    v dist {[0 : 63] := 1, [64 : 127] := 1};
    unique {v, p};
    solve v before p;
  }
  // Not solved with the container's constraints: the array and the object are not
  // variables of its solver
  constraint c_arr {foreach (arr[i]) arr[i] < 4'd3;}
  constraint c_sub {s.x < 5'd4;}
  function new();
    s = new;
    for (int i = 1; i < 128; i += 2) odds.push_back(7'(i));
  endfunction
endclass

class Dyn;
  rand Item a[];
  rand bit [6:0] w;
  constraint c_g {
    foreach (a[i]) a[i].v > 7'd16;
    w == a[0].v;
  }
  function new(int n);
    a = new[n];
    foreach (a[i]) a[i] = new;
  endfunction
endclass

class Que;
  rand Item q[$];
  constraint c_g {foreach (q[i]) q[i].v < 7'd40;}
endclass

// Reallocates the array before each randomize()
class Realloc extends Dyn;
  int n;
  function new();
    super.new(1);
  endfunction
  function void pre_randomize();
    a = new[n];
    foreach (a[i]) a[i] = new;
  endfunction
endclass

// Array declared in the base class, constrained in two derived ones
class ArrBase;
  rand Item a[];
endclass

class ArrDerived extends ArrBase;
  constraint c_d {foreach (a[i]) a[i].v != 7'd17;}
endclass

class ArrDerived2 extends ArrBase;
  constraint c_d2 {foreach (a[i]) a[i].v != 7'd19;}
endclass

module t;
  task automatic check_items(Item items[$], int above, int below);
    foreach (items[i]) begin
      `checkd(items[i].v[0], 1'b1);
      `checkd(items[i].v < 7'd110, 1'b1);
      `checkd(items[i].v inside {7'd17, 7'd19, 7'd21}, 1'b0);
      `checkd(int'(items[i].v) > above, 1'b1);
      `checkd(int'(items[i].v) < below, 1'b1);
      `checkd(items[i].u < 15'd1000, 1'b1);
      `checkd(items[i].p < 7'd100, 1'b1);
      `checkd(items[i].p != items[i].v, 1'b1);
    end
  endtask

  task automatic test_dyn;
    Dyn d = new(3);
    int randomize_result;
    int overridden = 0;
    repeat (20) begin
      randomize_result = d.randomize();
      `checkd(randomize_result, 1);
      check_items(d.a, 16, 128);
      `checkd(d.w, d.a[0].v);
      if (d.a[0].p >= 7'd10) ++overridden;
    end
    `checkd(overridden > 0, 1'b1);
    // randomize() with, first on a new object: the objects' constraints still apply
    d = new(2);
    repeat (20) begin
      randomize_result = d.randomize() with {a[1].v < 7'd24;};
      `checkd(randomize_result, 1);
      check_items(d.a, 16, 128);
      `checkd(d.a[1].v < 7'd24, 1'b1);
    end
  endtask

  task automatic test_queue;
    Que qu = new;
    int randomize_result;
    for (int n = 0; n < 4; ++n) begin
      Item it = new;
      // Also randomized on its own, with the constraints of its member object
      randomize_result = it.randomize();
      `checkd(randomize_result, 1);
      `checkd(it.v[0], 1'b1);
      `checkd(it.s.x != 5'd3, 1'b1);
      qu.q.push_back(it);
      repeat (5) begin
        randomize_result = qu.randomize();
        `checkd(randomize_result, 1);
        `checkd(qu.q.size(), n + 1);
        check_items(qu.q, 0, 40);
      end
    end
  endtask

  task automatic test_realloc;
    Realloc r = new;
    int randomize_result;
    for (int n = 1; n < 6; ++n) begin
      r.n = (n * 3) % 5 + 1;  // Grows and shrinks
      randomize_result = r.randomize();
      `checkd(randomize_result, 1);
      `checkd(r.a.size(), (n * 3) % 5 + 1);
      check_items(r.a, 16, 128);
    end
  endtask

  task automatic test_removed;
    // Objects removed from or replaced in the array are left alone
    Dyn d = new(4);
    Item removed;
    Item replaced;
    int randomize_result;
    randomize_result = d.randomize();
    `checkd(randomize_result, 1);
    removed = d.a[3];
    replaced = d.a[1];
    removed.v = 7'd2;
    replaced.v = 7'd4;
    d.a = new[3] (d.a);
    d.a[1] = new;
    repeat (10) begin
      randomize_result = d.randomize();
      `checkd(randomize_result, 1);
      check_items(d.a, 16, 128);
      `checkd(removed.v, 7'd2);
      `checkd(replaced.v, 7'd4);
    end
  endtask

  task automatic test_inherited;
    ArrDerived ad = new;
    ArrDerived2 ad2 = new;
    int randomize_result;
    ad.a = new[2];
    foreach (ad.a[i]) ad.a[i] = new;
    ad2.a = new[2];
    foreach (ad2.a[i]) ad2.a[i] = new;
    repeat (20) begin
      randomize_result = ad.randomize();
      `checkd(randomize_result, 1);
      check_items(ad.a, 0, 128);
      `checkd(ad.a[0].v != 7'd17, 1'b1);
      randomize_result = ad2.randomize();
      `checkd(randomize_result, 1);
      check_items(ad2.a, 0, 128);
      `checkd(ad2.a[0].v != 7'd19, 1'b1);
    end
  endtask

  initial begin
    test_dyn();
    test_queue();
    test_realloc();
    test_removed();
    test_inherited();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
