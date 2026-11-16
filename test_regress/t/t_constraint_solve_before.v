// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// Test solve...before constraint (IEEE 1800-2023 18.5.11)
// Verifies phased solving: 'before' variables are determined first,
// then 'after' variables are solved with all constraints applied.

/* verilator lint_off UNSIGNED */

module t;

  // Test: solve with conditional constraints
  class Packet;
    rand bit [2:0] mode;
    rand bit [7:0] data;

    constraint c_order {
      solve mode before data;
      mode inside {[0:3]};
      if (mode == 0) data == 8'h00;
      else if (mode == 1) data inside {[8'h01:8'h0f]};
      else data < 8'h80;
    }
  endclass

  // Test: basic solve before with range constraints
  class Simple;
    rand bit [3:0] x;
    rand bit [3:0] y;

    constraint c {
      solve x before y;
      x inside {[1:5]};
      y > x;
      y < 4'hf;
    }
  endclass

  // Test: multi-level solve before (a -> b -> c)
  class MultiLevel;
    rand bit [3:0] a;
    rand bit [3:0] b;
    rand bit [3:0] c;

    constraint c_order {
      solve a before b;
      solve b before c;
      a inside {[1:3]};
      b > a;
      b < 8;
      c > b;
      c < 4'hf;
    }
  endclass

  // Test 4: solve before on members of a rand member object, with the class
  // randomized as a rand member of other objects (global constraints, IEEE 1800-2023 18.5.8)
  class Coord;
    rand bit [7:0] x;
    rand bit [7:0] y;
    rand bit [3:0] arr[2];
    rand bit [3:0] darr[];
    function new();
      darr = new[3];
    endfunction
  endclass

  class Req;
    rand bit s;
    rand Coord c;
    constraint c_order {
      solve s before c.x, c.y;
      s -> c.x == 0;
      solve s before c.arr[1];
      c.arr[1] != 4'(s);
      foreach (c.darr[i]) {
        solve s before c.darr[i];
        c.darr[i] != 4'(s);
      }
    }
    function new();
      c = new;
    endfunction
  endclass

  class Top;
    rand Req r;
    function new();
      r = new;
    endfunction
  endclass

  class Top2;
    rand Top t;
    function new();
      t = new;
    endfunction
  endclass

  initial begin
    Packet p;
    Simple s;
    MultiLevel m;
    int ok;
    int randomize_result;

    // Test: Packet with conditional constraints
    p = new;
    repeat (20) begin
      randomize_result = p.randomize();
      `checkd(randomize_result, 1);
      `check_range(p.mode, 0, 3);
      if (p.mode == 0) `checkd(p.data, 0);
      if (p.mode == 1) begin
        `check_range(p.data, 1, 15);
      end
      if (p.mode >= 2) begin
        ok = (p.data < 8'h80) ? 1 : 0;
        `checkd(ok, 1);
      end
    end

    // Test: Simple range constraints
    s = new;
    repeat (20) begin
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      `check_range(s.x, 1, 5);
      ok = (s.y > s.x) ? 1 : 0;
      `checkd(ok, 1);
      ok = (s.y < 4'hf) ? 1 : 0;
      `checkd(ok, 1);
    end

    // Test: Multi-level chain
    m = new;
    repeat (20) begin
      randomize_result = m.randomize();
      `checkd(randomize_result, 1);
      `check_range(m.a, 1, 3);
      ok = (m.b > m.a && m.b < 8) ? 1 : 0;
      `checkd(ok, 1);
      ok = (m.c > m.b && m.c < 4'hf) ? 1 : 0;
      `checkd(ok, 1);
    end

    // Test 4: Nested member objects; without the ordering s is rarely 1
    begin
      automatic Req req = new;
      automatic Top top = new;
      automatic Top2 top2 = new;
      automatic int req_count = 0;
      automatic int top_count = 0;
      automatic int top2_count = 0;
      repeat (200) begin
        randomize_result = req.randomize();
        `checkd(randomize_result, 1);
        randomize_result = top.randomize();
        `checkd(randomize_result, 1);
        randomize_result = top2.randomize();
        `checkd(randomize_result, 1);
        if (top.r.s) `checkd(top.r.c.x, 0);
        if (top2.t.r.s) `checkd(top2.t.r.c.x, 0);
        ok = (top.r.c.arr[1] != 4'(top.r.s) && top.r.c.darr[2] != 4'(top.r.s)) ? 1 : 0;
        `checkd(ok, 1);
        req_count += int'(req.s);
        top_count += int'(top.r.s);
        top2_count += int'(top2.t.r.s);
      end
      `check_range(req_count, 60, 140);
      `check_range(top_count, 60, 140);
      `check_range(top2_count, 60, 140);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
