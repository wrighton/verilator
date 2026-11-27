// DESCRIPTION: Verilator: Static rand members of objects the randomization does not have
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

class leaf_t;
  static rand bit [6:0] shared;
  constraint c_shared {shared inside {[40 : 90]};}
endclass

// Test: the member is random only while the object reaches a leaf_t through a handle that is
// not null, whose rand_mode is on and that is randomized
class holder_t;
  rand bit [6:0] x;
  rand leaf_t leaf;
  constraint c {x == leaf_t::shared;}
endclass

// Test: through a static rand class handle, while it is not null
class static_holder_t;
  rand bit [6:0] x;
  static rand leaf_t sleaf;
  constraint c {x == leaf_t::shared;}
endclass

// Test: through arrays of handles, while an element is not null
class array_holder_t;
  rand bit [6:0] x;
  rand leaf_t fixed[1:3];
  rand leaf_t dyn[];
  rand leaf_t que[$];
  rand leaf_t assoc[int];
  rand leaf_t wild[*];
  constraint c {x == leaf_t::shared;}
endclass

// Test: through the handle of a derived class, so not for an object of the base class
class cfg_t;
  static rand bit [6:0] s;
  rand bit [6:0] v;
  constraint c_s {
    s inside {[10 : 20]};
    v == s + 1;
  }
endclass

class base_t;
  rand bit [6:0] k;
  constraint c {k == cfg_t::s;}
endclass

class derived_t extends base_t;
  rand cfg_t cfg;
  function new();
    cfg = new;
  endfunction
endclass

// Test: through a cycle of objects
typedef class ring_b_t;
class ring_a_t;
  rand bit [6:0] x;
  rand ring_b_t b;
  constraint c {x == leaf_t::shared;}
endclass

class ring_b_t;
  rand ring_a_t a;
  rand leaf_t leaf;
endclass

module t;
  initial begin
    begin
      automatic holder_t h = new;
      automatic bit seen[bit [6:0]];
      automatic int ok;
      // A null handle: a state variable
      leaf_t::shared = 35;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.x, 35);
      ok = h.randomize() with {x == 61;};
      `checkd(ok, 0);
      `checkd(leaf_t::shared, 35);
      // rand_mode(0): a state variable
      h.leaf = new;
      h.leaf.rand_mode(0);
      ok = h.randomize() with {x == 61;};
      `checkd(ok, 0);
      `checkd(leaf_t::shared, 35);
      h.leaf.rand_mode(1);
      // Not an argument of randomize(): a state variable
      ok = h.randomize(x);
      `checkd(ok, 1);
      `checkd(h.x, 35);
      `checkd(leaf_t::shared, 35);
      // Else random
      repeat (20) begin
        ok = h.randomize();
        `checkd(ok, 1);
        `checkd(h.x, leaf_t::shared);
        `checkd(leaf_t::shared inside {[40 : 90]}, 1);
        seen[leaf_t::shared] = 1;
      end
      `checkd(seen.size() > 2, 1);
    end
    begin
      automatic static_holder_t sh = new;
      automatic int ok;
      leaf_t::shared = 33;
      ok = sh.randomize() with {x == 62;};
      `checkd(ok, 0);
      `checkd(leaf_t::shared, 33);
      static_holder_t::sleaf = new;
      static_holder_t::sleaf.rand_mode(0);
      ok = sh.randomize() with {x == 62;};
      `checkd(ok, 0);
      `checkd(leaf_t::shared, 33);
      static_holder_t::sleaf.rand_mode(1);
      ok = sh.randomize() with {x == 62;};
      `checkd(ok, 1);
      `checkd(leaf_t::shared, 62);
    end
    begin
      automatic array_holder_t ah = new;
      automatic leaf_t one = new;
      automatic int ok;
      leaf_t::shared = 33;
      ok = ah.randomize() with {x == 58;};
      `checkd(ok, 0);
      `checkd(leaf_t::shared, 33);
      ah.fixed[2] = new;
      ok = ah.randomize() with {x == 58;};
      `checkd(ok, 1);
      `checkd(leaf_t::shared, 58);
      ah.fixed[2] = null;
      ah.dyn = new[2];
      ah.dyn[1] = new;
      ok = ah.randomize() with {x == 59;};
      `checkd(ok, 1);
      `checkd(leaf_t::shared, 59);
      ah.dyn.delete();
      ah.que.push_back(null);
      ah.que.push_back(one);
      ok = ah.randomize() with {x == 60;};
      `checkd(ok, 1);
      `checkd(leaf_t::shared, 60);
      ah.que.delete();
      ah.assoc[7] = new;
      ok = ah.randomize() with {x == 61;};
      `checkd(ok, 1);
      `checkd(leaf_t::shared, 61);
      ah.assoc.delete();
      ah.wild[5] = new;
      ok = ah.randomize() with {x == 62;};
      `checkd(ok, 1);
      `checkd(leaf_t::shared, 62);
      ah.wild.delete();
      ok = ah.randomize() with {x == 63;};
      `checkd(ok, 0);
      `checkd(leaf_t::shared, 62);
    end
    begin
      automatic derived_t d = new;
      automatic base_t b = new;
      automatic bit seen[bit [6:0]];
      automatic int ok;
      repeat (20) begin
        ok = d.randomize();
        `checkd(ok, 1);
        `checkd(d.k, cfg_t::s);
        `checkd(d.cfg.v, cfg_t::s + 1);
        seen[cfg_t::s] = 1;
      end
      `checkd(seen.size() > 2, 1);
      cfg_t::s = 15;
      ok = b.randomize();
      `checkd(ok, 1);
      `checkd(b.k, 15);
      `checkd(cfg_t::s, 15);
    end
    begin
      automatic ring_a_t a = new;
      automatic int ok;
      a.b = new;
      a.b.a = a;
      leaf_t::shared = 37;
      ok = a.randomize() with {x == 70;};
      `checkd(ok, 0);
      `checkd(leaf_t::shared, 37);
      a.b.leaf = new;
      ok = a.randomize() with {x == 70;};
      `checkd(ok, 1);
      `checkd(leaf_t::shared, 70);
      // Break the cycle, so that its objects are freed and runtime leak checking stays clean
      a.b.a = null;
    end

    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
