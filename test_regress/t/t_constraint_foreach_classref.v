// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH.
// SPDX-License-Identifier: CC0-1.0

// Test: Inline foreach constraints on dynamic arrays and queues of class objects

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

class Inner;
  rand bit [7:0] val;
  rand bit [3:0] tag;

  function new();
    val = 0;
    tag = 0;
  endfunction
endclass

class OuterDyn;
  rand Inner items[];

  function new(int size = 3);
    items = new[size];
    foreach (items[i]) items[i] = new();
  endfunction
endclass

class OuterQueue;
  rand Inner items[$];

  function new(int size = 3);
    Inner tmp;
    for (int i = 0; i < size; i++) begin
      tmp = new();
      items.push_back(tmp);
    end
  endfunction
endclass

// A field of an object inside an object of a dynamic array element
class NestedHolder;
  rand Inner inner;

  function new();
    inner = new();
  endfunction
endclass

class NestedDyn;
  rand NestedHolder rows[];
  rand NestedHolder others[];
  // The same index over a shorter array is seen first
  constraint c_short {foreach (others[i]) rows[i].inner.val != 8'hfe;}
  constraint c_all {foreach (rows[i]) rows[i].inner.val inside {[8'hf0 : 8'hff]};}
  constraint c_const {rows[1].inner.tag == 4'h9;}

  function new();
    rows = new[12];
    foreach (rows[i]) rows[i] = new();
    others = new[2];
    foreach (others[i]) others[i] = new();
  endfunction
endclass

// Only under an 'if', which folds the foreach into one expression
class NestedDynGated;
  rand NestedHolder rows[];
  bit gate;
  constraint c_gated {
    if (gate) {
      foreach (rows[i]) rows[i].inner.val < 8'h10;
    }
  }

  function new();
    rows = new[5];
    foreach (rows[i]) rows[i] = new();
  endfunction
endclass

// An element of an associative array whose key is computed by a method call
class NestedAssocKey;
  rand NestedHolder amap[int];
  int keys[$];
  constraint c_key {amap[keys.size() - 1].inner.val == 8'h21;}

  function new();
    for (int i = 0; i < 3; ++i) begin
      amap[i] = new();
      keys.push_back(i);
    end
  endfunction
endclass

// A shorter domain of keys first, over an associative array
class NestedAssocShort;
  rand NestedHolder amap[int];
  rand NestedHolder subset[int];
  constraint c_short {foreach (subset[k]) amap[k].inner.val != 8'hfe;}
  constraint c_all {foreach (amap[k]) amap[k].inner.val inside {[8'hf0 : 8'hff]};}

  function new();
    for (int i = 0; i < 4; ++i) amap[i] = new();
    subset[0] = new();
  endfunction
endclass

// The same associative arrays with no class constraint
class NestedAssocFree;
  rand NestedHolder amap[int];
  rand NestedHolder subset[int];

  function new();
    for (int i = 0; i < 4; ++i) amap[i] = new();
    subset[0] = new();
  endfunction
endclass

// The same objects with no class constraint, so an inline constraint registers them
class NestedDynFree;
  rand NestedHolder rows[];
  rand NestedHolder others[];

  function new();
    rows = new[12];
    foreach (rows[i]) rows[i] = new();
    others = new[2];
    foreach (others[i]) others[i] = new();
  endfunction
endclass

// A null element, whose constraint its guard eliminates (IEEE 1800-2023 18.5.12)
class NestedDynNull;
  rand NestedHolder rows[];
  constraint c {foreach (rows[i]) if (rows[i] != null) rows[i].inner.val == 8'h33;}

  function new();
    rows = new[3];
    rows[0] = new();
    rows[2] = new();
  endfunction
endclass

module t;
  OuterDyn od;
  OuterDyn od_arr[5];
  OuterQueue oq;

  initial begin
    // === Test 1: Dynamic array with inline foreach constraint ===
    od = new(3);

    if (od.randomize() with {
          foreach (items[i]) {
            items[i].val > 10;
            items[i].val < 200;
            items[i].tag > 0;
          }
        } == 0) begin
      $display("FAIL: dyn randomize() returned 0");
      $stop;
    end

    foreach (od.items[i]) begin
      if (!(od.items[i].val > 10 && od.items[i].val < 200)) begin
        $display("FAIL: dyn items[%0d].val=%0d out of range", i, od.items[i].val);
        $stop;
      end
      if (od.items[i].tag == 0) begin
        $display("FAIL: dyn items[%0d].tag=%0d should be > 0", i, od.items[i].tag);
        $stop;
      end
    end

    // === Test 2: Empty dynamic array (should succeed trivially) ===
    od = new(0);

    if (od.randomize() with {
          foreach (items[i]) {
            items[i].val > 10;
          }
        } == 0) begin
      $display("FAIL: empty dyn randomize() returned 0");
      $stop;
    end

    // === Test 3: Queue with inline foreach constraint ===
    oq = new(3);

    if (oq.randomize() with {
          foreach (items[i]) {
            items[i].val > 50;
            items[i].val < 150;
            items[i].tag > 0;
          }
        } == 0) begin
      $display("FAIL: queue randomize() returned 0");
      $stop;
    end

    foreach (oq.items[i]) begin
      if (!(oq.items[i].val > 50 && oq.items[i].val < 150)) begin
        $display("FAIL: queue items[%0d].val=%0d out of range", i, oq.items[i].val);
        $stop;
      end
      if (oq.items[i].tag == 0) begin
        $display("FAIL: queue items[%0d].tag=%0d should be > 0", i, oq.items[i].tag);
        $stop;
      end
    end

    // === Test 4: Array of objects with inline constraint for sub-object members ===
    // Verifies member resolution AND runtime enforcement when randomize()
    // target is array-indexed (regression test for verilator/verilator#7431)
    foreach (od_arr[i]) begin
      od_arr[i] = new(3);
      assert(od_arr[i].randomize() with {
        od_arr[i].items[0].val > 8'd10;
        od_arr[i].items[0].val < 8'd200;
        od_arr[i].items[0].tag > 0;
      } != 0);

      if (!(od_arr[i].items[0].val > 10 && od_arr[i].items[0].val < 200)) begin
        $display("FAIL: od_arr[%0d].items[0].val=%0d out of range",
                 i, od_arr[i].items[0].val);
        $stop;
      end
      if (od_arr[i].items[0].tag == 0) begin
        $display("FAIL: od_arr[%0d].items[0].tag=%0d should be > 0",
                 i, od_arr[i].items[0].tag);
        $stop;
      end
    end

    begin
      automatic NestedDyn nd = new;
      automatic int result;
      repeat (8) begin
        result = nd.randomize();
        `checkd(result, 1);
        `checkd(nd.rows[1].inner.tag, 4'h9);
        foreach (nd.rows[i]) begin
          `checkd(nd.rows[i].inner.val >= 8'hf0, 1);
          if (i < 2) `checkd(nd.rows[i].inner.val != 8'hfe, 1);
        end
      end
    end

    begin
      automatic NestedDynGated ng = new;
      automatic int result;
      automatic int high = 0;
      repeat (4) begin
        result = ng.randomize();
        `checkd(result, 1);
        foreach (ng.rows[i]) if (ng.rows[i].inner.val >= 8'h10) ++high;
      end
      `checkd(high > 0, 1);
      ng.gate = 1'b1;
      repeat (8) begin
        result = ng.randomize();
        `checkd(result, 1);
        foreach (ng.rows[i]) `checkd(ng.rows[i].inner.val < 8'h10, 1);
      end
    end

    begin
      automatic NestedDynFree nf = new;
      automatic int result;
      repeat (8) begin
        result = nf.randomize() with {
          foreach (others[i]) rows[i].inner.val != 8'h4d;
          foreach (rows[i]) rows[i].inner.val inside {[8'h40 : 8'h4f]};
        };
        `checkd(result, 1);
        foreach (nf.rows[i]) begin
          `checkd(nf.rows[i].inner.val inside {[8'h40 : 8'h4f]}, 1);
          if (i < 2) `checkd(nf.rows[i].inner.val != 8'h4d, 1);
        end
      end
    end

    begin
      automatic NestedAssocKey na = new;
      automatic int result;
      repeat (2) begin
        result = na.randomize();
        `checkd(result, 1);
        `checkd(na.amap[2].inner.val, 8'h21);
      end
    end

    begin
      automatic NestedAssocShort ns = new;
      automatic int result;
      repeat (16) begin
        result = ns.randomize();
        `checkd(result, 1);
        foreach (ns.amap[k]) `checkd(ns.amap[k].inner.val >= 8'hf0, 1);
        `checkd(ns.amap[0].inner.val != 8'hfe, 1);
      end
    end

    begin
      automatic NestedAssocFree nf = new;
      automatic int result;
      repeat (16) begin
        result = nf.randomize() with {
          foreach (subset[k]) amap[k].inner.val != 8'h4d;
          foreach (amap[k]) amap[k].inner.val inside {[8'h40 : 8'h4f]};
        };
        `checkd(result, 1);
        foreach (nf.amap[k]) `checkd(nf.amap[k].inner.val inside {[8'h40 : 8'h4f]}, 1);
        `checkd(nf.amap[0].inner.val != 8'h4d, 1);
      end
    end

    begin
      automatic NestedDynNull nn = new;
      automatic int result;
      result = nn.randomize();
      `checkd(result, 1);
      `checkd(nn.rows[0].inner.val, 8'h33);
      `checkd(nn.rows[2].inner.val, 8'h33);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
