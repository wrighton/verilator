// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Variables of the caller's scope in an inline constraint are state values,
// even when the caller declares them rand (IEEE 1800-2023 18.7)

typedef int int_arr_t[];

typedef struct {int unsigned a;} pair_t;

class Item;
  rand int unsigned x;
  rand int unsigned y;
  static int unsigned bound;
  // Same class as the object: local::x is this object's x, not the peer's
  function int randomize_peer(Item peer);
    return peer.randomize() with {
      x inside {[4:5]};
      x != local::x;
    };
  endfunction
endclass

class Other;
  static rand int unsigned s;
endclass

function automatic Item mk(int unsigned x);
  mk = new;
  mk.x = x;
endfunction

class Holder;
  rand Item q[$];
endclass

// Builds a list of items with unique (x, y) pairs, each excluding the earlier ones
class UniqueList;
  rand Item q[$];
  int n = 16;
  function void post_randomize();
    automatic int randomize_result;
    for (int i = 0; i < n; i++) begin
      automatic Item c = new;
      randomize_result = c.randomize() with {
        c.x inside {[1:4]};
        c.y inside {[1:4]};
        foreach (q[j]) {
          !(c.x == q[j].x && c.y == q[j].y);
        }
      };
      `checkd(randomize_result, 1);
      q.push_back(c);
    end
  endfunction
endclass

class Caller;
  rand Item q[$];
  rand Item dyn[];
  rand Item fixd[3];
  rand Item assoc[int];
  rand Item h;
  rand pair_t sq[$];
  rand pair_t s;
  rand int unsigned lim;
  rand Holder hold;
  rand int_arr_t md[];
  rand int unsigned idx;

  function void fill();
    dyn = new[3];
    md = new[2];
    md[1] = new[2];
    hold = new;
    for (int i = 0; i < 3; i++) begin
      q.push_back(mk(i + 1));
      dyn[i] = mk(i + 1);
      fixd[i] = mk(i + 1);
      assoc[i * 5] = mk(i + 1);
      sq.push_back('{a: i + 1});
      hold.q.push_back(mk(i + 1));
    end
    h = mk(1);
    s.a = 2;
    lim = 3;
    md[1][1] = 4;
    Item::bound = 4;
    Other::s = 4;
    idx = 2;
  endfunction

  // The randomized x can only be 4 when the caller's values are honored
  function void check(Item c, int randomize_result);
    `checkd(randomize_result, 1);
    `checkd(c.x, 4);
    c.x = 0;
    foreach (q[j]) `checkd(q[j].x, j + 1);
    `checkd(h.x, 1);
    `checkd(s.a, 2);
    `checkd(lim, 3);
  endfunction

  function void run();
    automatic Item c = new;
    automatic int randomize_result;
    automatic int unsigned v;
    repeat (20) begin
      randomize_result = c.randomize() with {
        c.x inside {[1:4]};
        foreach (q[j]) c.x != q[j].x;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        foreach (q[j]) x != q[j].x;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        foreach (local::q[j]) x != local::q[j].x;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        x != q[0].x;
        x != q[1].x;
        x != q[2].x;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        foreach (dyn[j]) x != dyn[j].x;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        foreach (fixd[j]) x != fixd[j].x;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        foreach (assoc[j]) x != assoc[j].x;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        foreach (sq[j]) x != sq[j].a;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        foreach (hold.q[j]) x != hold.q[j].x;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[1:4]};
        x != h.x;
        x != s.a;
        x != lim;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {x == md[1][1];};
      check(c, randomize_result);
      randomize_result = c.randomize() with {
        x inside {[3:bound]};
        x != lim;
      };
      check(c, randomize_result);
      randomize_result = c.randomize() with {x == q[idx].x + 1;};
      check(c, randomize_result);
      `checkd(idx, 2);
      randomize_result = c.randomize() with {x == Other::s;};
      check(c, randomize_result);
      `checkd(Other::s, 4);
      c.x = 5;
      randomize_result = c.randomize_peer(h);
      `checkd(randomize_result, 1);
      `checkd(h.x, 4);
      `checkd(c.x, 5);
      h.x = 1;
      randomize_result = std::randomize(v) with {
        v inside {[1:4]};
        foreach (q[j]) v != q[j].x;
      };
      `checkd(randomize_result, 1);
      `checkd(v, 4);
    end
  endfunction
endclass

module t;
  initial begin
    automatic UniqueList u = new;
    automatic Caller c = new;
    automatic int randomize_result;
    randomize_result = u.randomize();
    `checkd(randomize_result, 1);
    `checkd(u.q.size(), 16);
    foreach (u.q[i]) begin
      foreach (u.q[j]) begin
        if (i < j) `checkd(u.q[i].x == u.q[j].x && u.q[i].y == u.q[j].y, 0);
      end
    end
    c.fill();
    c.run();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
