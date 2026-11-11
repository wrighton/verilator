// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Random index into a non-random array of unpacked structs or class handles,
// reading an integral member, or a member array as an 'inside' set

typedef struct {
  int dnoc_vc_q[$];
  int cnoc_vc_q[$];
} vc_pair_t;

class RtrCfg;
  vc_pair_t e2w[2];
  function new();
    e2w[0].cnoc_vc_q = '{1, 2};
    e2w[1].cnoc_vc_q = '{5, 6};
  endfunction
endclass

class SeqCfg;
  rand int unsigned slice;
  rand int vc;
  RtrCfg m_cfg = new;
  constraint c_slice {slice < 2;}
  constraint c_vc {vc inside {m_cfg.e2w[slice].cnoc_vc_q};}
endclass

typedef struct {
  bit [6:0] a;
  int q[$];
  bit [32:0] fa[3];
} elem_t;

class Item;
  rand bit [6:0] val;
  int nr;
  int q[$];
  function new(bit [6:0] v);
    val = v;
    nr = 2 * v;
  endfunction
endclass

class Holder;
  rand int idx;
  rand int j;
  rand int x;
  rand bit [6:0] x7;
  rand bit [32:0] x33;
  elem_t arr[];
  elem_t fixed[3:5];
  Item items[$];
  Item fitems[3];
  bit [6:0] m2[3:1][4:2];
  constraint c_size {j == 7 -> items[idx].q.size() == 3;}
  function new();
    arr = new[3];
    foreach (arr[i]) begin
      arr[i].a = 7'(10 + i);
      arr[i].fa = '{33'h1_0000_0000 + 33'(i), 33'h1_0000_0000 + 33'(2 * i), 33'(3 * i)};
    end
    arr[0].q = '{3, 4};
    arr[2].q = '{7, 8, 9};
    foreach (fixed[i]) begin
      fixed[i].a = 7'(20 + i);
      fixed[i].q = '{i};
    end
    for (int i = 0; i < 4; ++i) begin
      Item item = new(7'(30 + i));
      item.q = '{40 + i, 50 + i};
      items.push_back(item);
    end
    items[1].q = {};
    items[3].q.push_back(60);
    foreach (m2[i, k]) m2[i][k] = 7'(8 * i + k);
    fitems[0] = new(7'h55);
    fitems[1] = new(7'h66);
  endfunction
endclass

// Class constraint over struct members; out-of-range elements read as zero
class StructCons;
  rand int idx;
  rand int vc;
  elem_t arr[];
  constraint c_idx {idx inside {[-2 : 4]};}
  constraint c_vc {vc inside {arr[idx].q};}
endclass

// Members reached through handles that are null in some elements
class Leaf;
  int f;
endclass

class Node;
  Leaf leaf;
  Leaf leaves[2];
endclass

class Walker;
  rand int idx;
  Node nodes[$];
  constraint c_idx {idx inside {[0 : 2]};}
endclass

module t;
  // Repro: queue member of a struct in a fixed array of a member object
  task automatic check_repro();
    SeqCfg c = new;
    int randomize_result;
    int seen[int];
    repeat (60) begin
      randomize_result = c.randomize();
      `checkd(randomize_result, 1)
      if (!(c.vc inside {c.m_cfg.e2w[c.slice].cnoc_vc_q})) `stop;
      seen[c.vc] = 1;
    end
    `checkd(seen.num(), 4)
  endtask

  task automatic check_struct_cons();
    StructCons c = new;
    int randomize_result;
    int seen[int];
    c.arr = new[3];
    c.arr[0].q = '{3, 4};
    c.arr[2].q = '{7, 8, 9};
    repeat (80) begin
      randomize_result = c.randomize();
      `checkd(randomize_result, 1)
      // Element 1 has an empty set and indices -2, -1, 3, 4 do not exist
      if (!(c.idx inside {0, 2})) `stop;
      if (!(c.vc inside {c.arr[c.idx].q})) `stop;
      seen[c.vc] = 1;
    end
    `checkd(seen.num(), 5)
    c.arr[0].q = {};
    c.arr[2].q = {};
    randomize_result = c.randomize();
    `checkd(randomize_result, 0)
  endtask

  task automatic check_holder();
    Holder h = new;
    int randomize_result;
    int seen[int];
    // Integral member of a dynamic array element, including nonexistent elements
    for (int pos = 0; pos < 3; ++pos) begin
      h.x7 = 7'(10 + pos);
      h.x7.rand_mode(0);
      randomize_result = h.randomize() with {
        idx inside {[-3 : 5]};
        x7 == arr[idx].a;
      };
      `checkd(randomize_result, 1)
      `checkd(h.idx, pos)
    end
    h.x7 = 0;
    repeat (40) begin
      randomize_result = h.randomize() with {
        idx inside {[-3 : 5]};
        x7 == arr[idx].a;
      };
      `checkd(randomize_result, 1)
      if (h.idx inside {[0 : 2]}) `stop;
      seen[h.idx] = 1;
    end
    `checkd(seen.num(), 6)
    seen.delete();
    h.x7.rand_mode(1);
    // Element of a member array wider than 32 bits, and a member queue size
    repeat (40) begin
      randomize_result = h.randomize() with {
        idx inside {[0 : 2]};
        arr[idx].fa[2] != 0;
        arr[idx].q.size() >= 2;
        x33 == arr[idx].fa[1];
      };
      `checkd(randomize_result, 1)
      `checkd(h.idx, 2)
      `checkd(h.x33, 33'h1_0000_0004)
    end
    // Second random index into the member queue of the selected element
    foreach (h.arr[pos]) begin
      foreach (h.arr[pos].q[k]) begin
        randomize_result = h.randomize() with {
          x == arr[idx].q[j];
          x == local::h.arr[pos].q[k];
        };
        `checkd(randomize_result, 1)
        `checkd(h.idx, pos)
        `checkd(h.j, k)
      end
    end
    // Fixed-size array with a non-zero low bound
    repeat (40) begin
      randomize_result = h.randomize() with {
        idx inside {[3 : 5]};
        x inside {fixed[idx].q};
        x7 == fixed[idx].a;
      };
      `checkd(randomize_result, 1)
      `checkd(h.x, h.idx)
      `checkd(int'(h.x7), 20 + h.idx)
      seen[h.idx] = 1;
    end
    `checkd(seen.num(), 3)
    seen.delete();
    // Queue of class handles: a rand property of a non-random object is state
    foreach (h.items[pos]) begin
      randomize_result = h.randomize() with {
        x7 == items[idx].val;
        x7 == 7'(30 + pos);
      };
      `checkd(randomize_result, 1)
      `checkd(h.idx, pos)
      `checkd(h.items[0].val, 30)
      // Non-random property, element of a member queue, member queue size
      randomize_result = h.randomize() with {
        x == items[{25'd0, fitems[0].val} - 'h55 + idx].nr;
        x == 60 + 2 * local::pos;
      };
      `checkd(randomize_result, 1)
      `checkd(h.idx, pos)
      if (pos == 1) continue;  // Empty queue
      randomize_result = h.randomize() with {
        x == items[idx].q[j];
        x == 50 + local::pos;
      };
      `checkd(randomize_result, 1)
      `checkd(h.idx, pos)
      `checkd(h.j, 1)
    end
    repeat (20) begin
      randomize_result = h.randomize() with {j == 7;};
      `checkd(randomize_result, 1)
      `checkd(h.idx, 3)
    end
    // Member queue of a class handle as an 'inside' set; items[1] has an empty set
    repeat (80) begin
      randomize_result = h.randomize() with {x inside {items[idx].q};};
      `checkd(randomize_result, 1)
      if (h.idx == 1) `stop;
      if (!(h.x inside {h.items[h.idx].q})) `stop;
      seen[h.x] = 1;
    end
    `checkd(seen.num(), 7)
    seen.delete();
    // Multi-dimensional fixed-size array, one and two random indices
    foreach (h.m2[pos, k]) begin
      randomize_result = h.randomize() with {
        idx inside {[1 : 3]};
        x7 == m2[idx][3];
        x7 == local::h.m2[pos][3];
      };
      `checkd(randomize_result, 1)
      `checkd(h.idx, pos)
      randomize_result = h.randomize() with {
        idx inside {[1 : 3]};
        j inside {[2 : 4]};
        x7 == m2[idx][j];
        x7 == local::h.m2[pos][k];
      };
      `checkd(randomize_result, 1)
      `checkd(h.idx, pos)
      `checkd(h.j, k)
    end
    // Random index expression that also reads a property of another object
    randomize_result = h.randomize() with {
      idx inside {[0 : 1]};
      x7 == m2[fitems[0].nr + idx - 'haa][3];
      x7 == local::h.m2[1][3];
    };
    `checkd(randomize_result, 1)
    `checkd(h.idx, 1)
    // Rand property through a constant index into a non-random handle array
    randomize_result = h.randomize() with {x7 == fitems[1].val;};
    `checkd(randomize_result, 1)
    `checkd(int'(h.x7), 'h66)
    randomize_result = h.randomize() with {x7 == items[2].val;};
    `checkd(randomize_result, 1)
    `checkd(int'(h.x7), 32)
    // Fixed-size array of class handles, one null
    repeat (30) begin
      randomize_result = h.randomize() with {
        idx inside {[0 : 2]};
        x7 == fitems[idx].val;
        x7 != 0;
      };
      `checkd(randomize_result, 1)
      `checkd(int'(h.x7), h.idx == 0 ? 'h55 : 'h66)
      seen[h.idx] = 1;
    end
    `checkd(seen.num(), 2)
  endtask

  // std::randomize() with a local index into a local queue
  function automatic int pick_vc(int sel, output int vc);
    vc_pair_t pairs[$];
    vc_pair_t pair;
    int idx;
    int randomize_result;
    pair.dnoc_vc_q = '{11, 12};
    pairs.push_back(pair);
    pair.dnoc_vc_q = '{13};
    pairs.push_back(pair);
    pair.dnoc_vc_q = '{14, 15};
    pairs.push_back(pair);
    pairs[sel].dnoc_vc_q = {};
    randomize_result = std::randomize(idx, vc) with {vc inside {pairs[idx].dnoc_vc_q};};
    `checkd(randomize_result, 1)
    if (!(vc inside {pairs[idx].dnoc_vc_q})) `stop;
    return idx;
  endfunction
  // std::randomize() with a local index into a local queue of class handles
  function automatic int pick_item(int pos);
    Item items[$];
    int idx;
    int x;
    int randomize_result;
    for (int i = 0; i < 3; ++i) begin
      Item item = new(7'(i + 1));
      items.push_back(item);
    end
    randomize_result = std::randomize(idx, x) with {
      x == items[idx].nr;
      x == 2 * pos + 2;
    };
    `checkd(randomize_result, 1)
    return idx;
  endfunction
  task automatic check_std_randomize();
    int seen[int];
    int vc;
    int idx;
    for (int sel = 0; sel < 3; ++sel) begin
      repeat (30) begin
        idx = pick_vc(sel, vc);
        if (idx == sel) `stop;
        seen[vc] = 1;
      end
    end
    `checkd(seen.num(), 5)
    for (int pos = 0; pos < 3; ++pos) `checkd(pick_item(pos), pos)
  endtask

  task automatic check_nested_null();
    Walker w = new;
    int randomize_result;
    repeat (3) begin
      Node node = new;
      w.nodes.push_back(node);
    end
    w.nodes[1].leaf = new;
    w.nodes[1].leaf.f = 3;
    w.nodes[2].leaf = new;
    w.nodes[2].leaf.f = 5;
    w.nodes[0].leaves[1] = new;
    w.nodes[0].leaves[1].f = 7;
    w.nodes[2].leaves[1] = new;
    w.nodes[2].leaves[1].f = 9;
    repeat (10) begin
      randomize_result = w.randomize() with {nodes[idx].leaf.f == 3;};
      `checkd(randomize_result, 1)
      `checkd(w.idx, 1)
      randomize_result = w.randomize() with {nodes[idx].leaves[1].f == 7;};
      `checkd(randomize_result, 1)
      `checkd(w.idx, 0)
      // nodes[0].leaf is null, so its element reads as zero
      randomize_result = w.randomize() with {nodes[idx].leaf.f != 3; nodes[idx].leaf.f != 5;};
      `checkd(randomize_result, 1)
      `checkd(w.idx, 0)
    end
  endtask

  initial begin
    check_repro();
    check_nested_null();
    check_struct_cons();
    check_holder();
    check_std_randomize();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
