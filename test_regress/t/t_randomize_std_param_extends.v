// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Test std::randomize() inside classes extending parameterized base classes.
// Derived from issue #7409 (wsnyder's minimized reproduction).

package my_pkg;

  class uvm_sequence_item;
  endclass

  class uvm_sequence #(
      parameter type T = int
  );
  endclass

  // std::randomize in class extending parameterized base (the bug)
  class foo_t extends uvm_sequence #(uvm_sequence_item);
    task test_std_rand();
      int unsigned my_var;
      int ok;
      ok = std::randomize(my_var);
      `checkd(ok, 1);
    endtask
  endclass

  // std::randomize with 'with' clause
  class bar_t extends uvm_sequence #(uvm_sequence_item);
    task test_std_rand_with();
      int unsigned v;
      int ok;
      ok = std::randomize(v) with {v inside {[1 : 100]};};
      `checkd(ok, 1);
      if (v < 1 || v > 100) begin
        $write("%%Error: constraint violated: v=%0d\n", v);
        `stop;
      end
    endtask
  endclass

  // this.randomize() regression for parameterized-derived class
  class rand_t extends uvm_sequence #(uvm_sequence_item);
    rand int unsigned x;
    constraint c_x {x inside {[1 : 50]};}
  endclass

endpackage

// std::randomize outside package, multi-level parameterized inheritance
class base_c #(
    type T = int
);
  T item;
endclass

class mid_c extends base_c #(int);
endclass

class leaf_c extends mid_c;
  task test_std_rand();
    int unsigned v;
    int ok;
    ok = std::randomize(v);
    `checkd(ok, 1);
  endtask
endclass

module t;
  typedef struct {
    int qp;
    logic [1:0] profile;
  } item_s;

  class Base #(parameter int CFG = 0);
    item_s items[$];
    int limit = 100;
  endclass

  class Derived #(parameter int CFG = 0) extends Base #(CFG);
    // IEEE 1800-2023 18.12.1: non-randomized names remain in the calling scope.
    task body(output int got);
      int profile;
      int ok;
      items.shuffle();
      ok = std::randomize(profile) with {
        profile inside {[0:2]};
        profile != int'(items[0].profile);
      };
      `checkd(ok, 1);
      got = profile;
    endtask

    // A method argument shadows an inherited state member, even after deferral.
    task check_scalar(int limit);
      int value;
      int ok;
      ok = std::randomize(value) with {value == limit;};
      `checkd(ok, 1);
      `checkd(value, limit);
    endtask
  endclass

  initial begin
    automatic my_pkg::foo_t foo = new;
    automatic my_pkg::bar_t bar = new;
    automatic my_pkg::rand_t rt = new;
    automatic leaf_c lc = new;
    int ok;

    // Issue #7409 exact scenario: std::randomize in package class
    foo.test_std_rand();

    // std::randomize with 'with' clause
    bar.test_std_rand_with();

    // this.randomize() regression
    ok = rt.randomize();
    `checkd(ok, 1);
    if (rt.x < 1 || rt.x > 50) begin
      $write("%%Error: constraint violated: x=%0d\n", rt.x);
      `stop;
    end

    // Multi-level parameterized inheritance outside package
    lc.test_std_rand();

    begin
      automatic Derived #(1) d = new;
      automatic Derived #(2) d2 = new;
      item_s it;
      int p;
      it.qp = 7;
      it.profile = 2'd1;
      d.items.push_back(it);
      d2.items.push_back(it);
      for (int i = 0; i < 20; ++i) begin
        d.items[0].profile = 2'(i % 3);
        d.body(p);
        `checkd(p inside {[0:2]}, 1);
        `checkd(p != int'(d.items[0].profile), 1);
        d.check_scalar(i + 1);
        d2.body(p);
        `checkd(p inside {[0:2]}, 1);
        `checkd(p != 1, 1);
        d2.check_scalar(i + 2);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
