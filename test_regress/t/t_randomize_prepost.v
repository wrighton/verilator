// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef enum int {RANDOMIZED = 20} enumed_t;

class Base;
  int m_pre;
  rand enumed_t r;
  int m_post;

  function void pre_randomize;
    `checkd(m_pre, 0);
    `checkd(r, enumed_t'(0));
    `checkd(m_post, 0);
    m_pre = 10;
  endfunction

  function void post_randomize;
    `checkd(m_pre, 10);
    `checkd(r, RANDOMIZED);
    `checkd(m_post, 0);
    m_post = 30;
  endfunction
endclass

class Cls extends Base;
  int m_cpre;
  int m_cpost;
  function void pre_randomize;
    m_cpre = 111;
    super.pre_randomize();
  endfunction

  function void post_randomize;
    m_cpost = 222;
    super.post_randomize();
  endfunction
endclass

package emp_pkg;
  virtual class emp_sequence #(
      type REQ = int
  );
  endclass
  class emp_txn;
  endclass
  class emp_base_sequence extends emp_sequence #(emp_txn);
  endclass
  class emp_base_port_seq extends emp_base_sequence;
    function void pre_randomize();
      super.pre_randomize();
    endfunction
    function void post_randomize();
      super.post_randomize();
    endfunction
  endclass
endpackage

// A failed randomize() calls no post_randomize, of the object or of its rand
// members, and the constrained random variables keep their values (IEEE 1800-2023 18.6.3).
// Rand members randomized before the solve, as by randomize() with, are not covered.
class FailItem;
  rand bit [6:0] v;
  int m_post;
  constraint c_v {v < 10;}
  function void post_randomize;
    ++m_post;
  endfunction
endclass

class FailBase;
  rand bit [6:0] x;
  rand FailItem item;
  bit bad;
  int m_pre;
  int m_post;
  constraint c_x {bad -> x == 3 && x == 4;}
  function new;
    item = new;
  endfunction
  function void pre_randomize;
    ++m_pre;
  endfunction
  function void post_randomize;
    ++m_post;
  endfunction
endclass

class FailDerived extends FailBase;
  int m_dpost;
  function void post_randomize;
    ++m_dpost;
  endfunction
endclass

// A rand member object of a class also randomized on its own, which randomize() of
// the containing object randomizes by the member's own randomize()
class OwnItem;
  rand bit [6:0] v;
  int m_post;
  function void post_randomize;
    ++m_post;
  endfunction
endclass

class OwnBase;
  rand bit [6:0] x;
  rand bit [6:0] z;
  rand OwnItem item;
  bit bad;
  constraint c_x {bad -> x == 3 && x == 4;}
  function new;
    item = new;
  endfunction
endclass

module t;

  initial begin
    Cls c;
    int rand_result;

    c = new;
    rand_result = c.randomize();
    `checkd(rand_result, 1);
    `checkd(c.m_pre, 10);
    `checkd(c.m_cpre, 111);
    `checkd(c.r, RANDOMIZED);
    `checkd(c.m_post, 30);
    `checkd(c.m_cpost, 222);

    c = new;
    rand_result = c.randomize() with {r == RANDOMIZED;};
    `checkd(rand_result, 1);
    `checkd(c.m_pre, 10);
    `checkd(c.m_cpre, 111);
    `checkd(c.r, RANDOMIZED);
    `checkd(c.m_post, 30);
    `checkd(c.m_cpost, 222);

    begin
      OwnItem oi;
      OwnBase ob;
      oi = new;
      rand_result = oi.randomize();
      `checkd(rand_result, 1);
      `checkd(oi.m_post, 1);
      ob = new;
      ob.bad = 1;
      ob.x = 77;
      ob.z = 88;
      ob.item.v = 99;
      rand_result = ob.randomize();
      `checkd(rand_result, 0);
      `checkd(ob.item.m_post, 0);
      `checkd(ob.x, 77);
      `checkd(ob.z, 88);
      `checkd(ob.item.v, 99);
    end

    begin
      FailBase f;
      FailDerived fd;
      int n_item_post;
      f = new;
      f.bad = 1;
      f.x = 77;
      f.item.v = 55;
      rand_result = f.randomize();
      `checkd(rand_result, 0);
      `checkd(f.m_pre, 1);
      `checkd(f.m_post, 0);
      `checkd(f.item.m_post, 0);
      `checkd(f.x, 77);
      `checkd(f.item.v, 55);
      f.bad = 0;
      rand_result = f.randomize() with {x == 1; x == 2;};
      `checkd(rand_result, 0);
      `checkd(f.m_pre, 2);
      `checkd(f.m_post, 0);
      `checkd(f.x, 77);
      n_item_post = f.item.m_post;
      rand_result = f.randomize();
      `checkd(rand_result, 1);
      `checkd(f.m_post, 1);
      `checkd(f.item.m_post, n_item_post + 1);

      // Through a base handle, reaching the derived post_randomize
      fd = new;
      f = fd;
      f.bad = 1;
      rand_result = f.randomize();
      `checkd(rand_result, 0);
      f.bad = 0;
      rand_result = f.randomize() with {x == 1; x == 2;};
      `checkd(rand_result, 0);
      `checkd(fd.m_dpost, 0);
      n_item_post = fd.item.m_post;
      rand_result = f.randomize() with {x == 5;};
      `checkd(rand_result, 1);
      `checkd(fd.x, 5);
      `checkd(fd.m_dpost, 1);
      `checkd(fd.item.m_post, n_item_post + 1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
