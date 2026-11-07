// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// Test solve...before constraint (IEEE 1800-2023 18.5.9)
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

  // Test 4: members of a packed struct, and other parts of a variable, are ordered on
  // their own. Solved together with kind, op is 0 in 128 of 131 solutions, ordered before
  // it in far fewer calls.
  typedef struct packed {
    bit [3:0] op;
    bit [6:0] kind;
    bit bypass;
    bit [3:0] pasid;
    bit [63:0] mmu;
  } cfg_t;

  class PackedPart;
    rand cfg_t cfg;
    rand bit [3:1][6:0] pa;
    rand bit [6:0] u;
    rand bit [6:0] v;
    rand bit [6:0] w;
    int idx = 7;
    int k = 3;

    constraint c_order {
      solve cfg.op before cfg.kind;
      solve pa[k] before pa[k - 1];
      // Leaving bits of cfg between them unordered
      solve cfg.pasid before cfg.mmu[3:0];
      // Of a variable in no constraint, or out of range, so not ordered
      solve u[1:0] before w;
      solve v[idx] before w;
      solve v[idx - 1 +: 2] before w;
    }
    constraint c_values {
      cfg.op inside {[0:3]};
      (cfg.op != 0) -> cfg.kind == 0;
      cfg.bypass == 1;
      cfg.pasid == 0;
      cfg.mmu == 64'h1234_5678_9abc_def0;
      pa[3] inside {[0:3]};
      (pa[3] != 0) -> pa[2] == 0;
      v != w;
    }
  endclass

  // Test 4, nested select: out of the range of pa2[0], pa2[0][j] with j = 7 does not select
  // pa2[1][0], so is not ordered; with j = 6 it orders bit 6 before ny, before bit 7. Likewise
  // p3[0][i][0] with i = 3, out of the range of p3[0], does not select p3[1][0][0].
  class NestedSel;
    rand bit [1:0][6:0] pa2;
    rand bit [2:0][2:0][2:0] p3;
    rand bit [2:0] ny;
    bit [2:0] j = 7;
    bit [1:0] i = 3;

    constraint c_order {
      pa2 != 0;
      p3 != 0;
      ny < 3'd7;
      solve pa2[0][j] before ny;
      solve ny before pa2[1][0];
      solve p3[0][i][0] before ny;
      solve ny before p3[1][0][0];
    }
  endclass

  // Test 5: a variable is solved after the predecessors of each of its parts, its other bits
  // as their own variable, as the solver log checked by the driver shows
  class MixedOrder;
    rand bit [6:0] mx;
    rand bit [3:0] mz;
    rand bit [2:0] my;

    constraint c_order {
      solve mx before my;
      solve mz before mx[3:0];
      mz inside {[0:3]};
      (mz != 0) -> mx[3:0] == 0;
      my < 3'd7;
    }
  endclass

`ifdef VERILATOR
  // Test 6: a circular ordering, which IEEE 1800-2023 18.5.9 forbids: Verilator reports it and
  // fails randomize(). Also through overlapping parts.
  class Circular;
    rand bit [3:0] a;
    rand bit [3:0] b;

    constraint c_order {
      solve a before b;
      solve b before a;
      a < b;
    }
  endclass

  class CircularPart;
    rand bit [3:0] a;
    rand bit [3:0] b;

    constraint c_order {
      solve a before b;
      solve b before a[1:0];
      a < b;
    }
  endclass
`endif

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

    // Test 4: Packed struct members and parts of packed variables
    begin
      automatic PackedPart pp = new;
      automatic int n_cfg = 0;
      automatic int n_arr = 0;
      repeat (200) begin
        randomize_result = pp.randomize();
        `checkd(randomize_result, 1);
        `check_range(pp.cfg.op, 0, 3);
        if (pp.cfg.op != 0) `checkd(pp.cfg.kind, 0);
        `checkd(pp.cfg.bypass, 1);
        `checkd(pp.cfg.pasid, 0);
        `checkh(pp.cfg.mmu, 64'h1234_5678_9abc_def0);
        `check_range(pp.pa[3], 0, 3);
        if (pp.pa[3] != 0) `checkd(pp.pa[2], 0);
        n_cfg += pp.cfg.op == 0;
        n_arr += pp.pa[3] == 0;
      end
      `check_range(n_cfg, 1, 160);
      `check_range(n_arr, 1, 160);
      // Nested select
      begin
        automatic NestedSel ns = new;
        randomize_result = ns.randomize();
        `checkd(randomize_result, 1);
        ns.j = 6;
        randomize_result = ns.randomize();
        `checkd(randomize_result, 1);
      end
    end

    // Test 5: Mixed whole and part ordering
    begin
      automatic MixedOrder mo = new;
      repeat (20) begin
        randomize_result = mo.randomize();
        `checkd(randomize_result, 1);
        `check_range(mo.mz, 0, 3);
        if (mo.mz != 0) `checkd(mo.mx[3:0], 0);
        `check_range(mo.my, 0, 6);
      end
    end

`ifdef VERILATOR
    // Test 6: Circular ordering, a Verilator diagnostic
    begin
      automatic Circular c = new;
      automatic CircularPart cp = new;
      c.a = 5;
      c.b = 6;
      randomize_result = c.randomize();
      `checkd(randomize_result, 0);
      `checkd(c.a, 5);
      `checkd(c.b, 6);
      randomize_result = cp.randomize();
      `checkd(randomize_result, 0);
    end
`endif

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
