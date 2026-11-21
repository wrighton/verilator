// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

typedef enum bit [1:0] { TXN_READ, TXN_WRITE } txn_e;

// Each constraint exercises one RHS shape allowed by IEEE 1800-2023 18.7.2
// (constraint_set on the right of the implication operator -> ).  `mode`
// selects which constraint contributes; the others are vacuous.
class Forms;
  rand bit [3:0] mode;
  rand bit [3:0] a;
  rand bit [3:0] b;
  rand bit [3:0] c;
  rand bit [31:0] address;
  rand txn_e txn_type;
  rand bit [7:0] arr [4];
  rand bit [3:0] uarr [3];

  // Bare expression (legacy form, supported pre-PR via expr->expr).
  constraint c_expr {
    (mode == 4'd0) -> b == 4'h9;
  }

  // Brace-block: the exact shape from issue #7300.
  constraint c_brace_repro {
    (mode == 4'd1) -> {
      if (txn_type inside {TXN_READ}) address % (1 << 4) == 0;
    }
  }

  // Brace-block with multiple statements.
  constraint c_brace_multi {
    (mode == 4'd2) -> {
      address[0]  == 1'b0;
      address[31] == 1'b0;
    }
  }

  // Bare if (without surrounding braces).
  constraint c_if {
    (mode == 4'd3) -> if (a == 4'h1) b == 4'h7;
  }

  // Bare if/else.
  constraint c_if_else {
    (mode == 4'd4) -> if (a == 4'h1) b == 4'ha;
                      else            b == 4'hb;
  }

  // Bare foreach.
  constraint c_foreach {
    (mode == 4'd5) -> foreach (arr[i]) arr[i] < 8'h40;
  }

  // Bare unique (uses the static-array form V3Randomize supports today).
  constraint c_unique {
    (mode == 4'd6) -> unique { uarr };
  }

  // Bare soft.
  constraint c_soft {
    (mode == 4'd7) -> soft b == 4'hd;
  }

  // Nested implication inside a brace block.
  constraint c_nested {
    (mode == 4'd8) -> {
      (a == 4'h0) -> { b == 4'h5; }
    }
  }
endclass

// Conditional `disable soft` is meta-level: V3Randomize hoists it into a
// runtime AstIf attached to the setup task so the directive only fires
// when its outer condition is true.  When override_flag==0, the soft
// `x == 4'h5` wins; when override_flag==1, the implication fires the
// disable AND the override `x == 4'hc`, so x must be 4'hc.
class DisSoft;
  bit override_flag;
  rand bit [3:0] x;
  constraint c_soft_x { soft x == 4'h5; }
  constraint c_override {
    (override_flag == 1'b1) -> disable soft x ;
    (override_flag == 1'b1) -> x == 4'hc ;
  }
endclass

// MemberSel target for `disable soft`.  Cross-object reference (inner.y)
// parses as AstMemberSel; disable-soft must extract the variable name from
// that node shape too.
class Inner;
  rand bit [3:0] y;
endclass
class DisSoftMember;
  bit override_flag;
  rand Inner inner;
  constraint c_soft_y { soft inner.y == 4'h5; }
  constraint c_override {
    (override_flag == 1'b1) -> disable soft inner.y ;
    (override_flag == 1'b1) -> inner.y == 4'hc ;
  }
  function new(); inner = new(); endfunction
endclass

// `disable soft` in BOTH then and else arms of a single if.  Exercises the
// hoist-list concat path in the else branch (a then-arm hoist already
// exists when the else-arm hoist is appended).  The hard constraint in each
// arm fires under its `pick` condition, and the soft constraint of the other
// variable is kept.  The condition variable `pick` is non-rand so the setup
// task sees its current value before the solver runs.
class DisSoftBothArms;
  bit [1:0] pick;
  rand bit [3:0] a;
  rand bit [3:0] b;
  constraint c_soft_a { soft a == 4'h7; }
  constraint c_soft_b { soft b == 4'h8; }
  constraint c_split {
    if (pick == 2'd0) { disable soft a; a == 4'h1; }
    else              { disable soft b; b == 4'h2; }
  }
endclass

// `disable soft` removes only the soft constraints its variable directly
// appears in (IEEE 1800-2023 18.5.13.2): not one that variable only guards,
// nor one on the same member of another object.
class DisSoftDirect;
  rand bit p;
  rand bit [6:0] q;
  rand bit [6:0] r;
  rand Inner a;
  rand Inner b;
  constraint c_p { p; }
  constraint c_guarded { p -> soft q == 7'd9; }
  constraint c_direct { soft !p || r == 7'd11; }
  constraint c_member { soft a.y == 4'h3; soft b.y == 4'h4; }
  constraint c_disable {
    disable soft p;
    disable soft a.y;
  }
  function new();
    a = new();
    b = new();
  endfunction
endclass

// `disable soft` of a field of an object in an array removes only the soft
// constraints of that object's field: constant indices into a fixed array, state
// indices narrower and wider than 32 bits into a dynamic array, a queue's last
// element, an associative array key, and a foreach index.
class DisSoftMid;
  rand Inner inner;
  function new();
    inner = new();
  endfunction
endclass

class DisSoftElems;
  rand Inner fixedArr[12];
  rand Inner dynArr[];
  bit [6:0] narrowIdx = 7'd10;
  longint wideIdx = 64'd4;
  rand DisSoftMid mids[12];
  rand Inner q[$];
  rand Inner amap[int];
  constraint c_fixed {
    soft fixedArr[1].y == 4'h7;
    soft fixedArr[10].y == 4'h5;
    soft fixedArr[11].y == 4'h6;
  }
  constraint c_dyn { foreach (dynArr[i]) soft dynArr[i].y == 4'h1; }
  constraint c_mids { soft mids[1].inner.y == 4'h5; soft mids[10].inner.y == 4'h6; }
  constraint c_q { soft q[0].y == 4'h2; soft q[2].y == 4'h9; }
  constraint c_amap { soft amap[-7].y == 4'h8; soft amap[7].y == 4'ha; }
  constraint c_disable {
    disable soft fixedArr[10].y;
    disable soft dynArr[narrowIdx].y;
    disable soft dynArr[wideIdx].y;
    disable soft mids[10].inner.y;
    disable soft q[$].y;
    disable soft amap[7].y;
  }
  function new();
    foreach (fixedArr[i]) fixedArr[i] = new();
    dynArr = new[12];
    foreach (dynArr[i]) dynArr[i] = new();
    foreach (mids[i]) mids[i] = new();
    repeat (3) begin
      automatic Inner e = new();
      q.push_back(e);
    end
    amap[-7] = new();
    amap[7] = new();
  endfunction
endclass

class DisSoftBinder;
  rand Inner objs[];
  constraint c_pref { foreach (objs[i]) soft objs[i].y == 4'h1; }
  constraint c_widen {
    foreach (objs[i]) {
      disable soft objs[i].y;
      soft objs[i].y inside {4'h1, 4'h2};
    }
  }
  function new();
    objs = new[12];
    foreach (objs[i]) objs[i] = new();
  endfunction
endclass

module t;
  Forms obj;
  DisSoft ds;
  int ok;

  initial begin
    obj = new();

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd0; };
      `checkd(ok, 1);
      `checkh(obj.b, 4'h9);
    end

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd1; txn_type == TXN_READ; };
      `checkd(ok, 1);
      `checkh(obj.address[3:0], 4'h0);
    end

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd2; };
      `checkd(ok, 1);
      `checkh(obj.address[0], 1'b0);
      `checkh(obj.address[31], 1'b0);
    end

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd3; a == 4'h1; };
      `checkd(ok, 1);
      `checkh(obj.b, 4'h7);
    end

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd4; a == 4'h1; };
      `checkd(ok, 1);
      `checkh(obj.b, 4'ha);
    end
    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd4; a == 4'h2; };
      `checkd(ok, 1);
      `checkh(obj.b, 4'hb);
    end

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd5; };
      `checkd(ok, 1);
      foreach (obj.arr[i]) `checkh(obj.arr[i] < 8'h40, 1'b1);
    end

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd6; };
      `checkd(ok, 1);
      `checkh(obj.uarr[0] == obj.uarr[1], 1'b0);
      `checkh(obj.uarr[0] == obj.uarr[2], 1'b0);
      `checkh(obj.uarr[1] == obj.uarr[2], 1'b0);
    end

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd7; };
      `checkd(ok, 1);
      `checkh(obj.b, 4'hd);
    end

    repeat (10) begin
      ok = obj.randomize() with { mode == 4'd8; a == 4'h0; };
      `checkd(ok, 1);
      `checkh(obj.b, 4'h5);
    end

    ds = new();
    ds.override_flag = 1'b0;
    repeat (10) begin
      ok = ds.randomize();
      `checkd(ok, 1);
      `checkh(ds.x, 4'h5);
    end
    ds.override_flag = 1'b1;
    repeat (10) begin
      ok = ds.randomize();
      `checkd(ok, 1);
      `checkh(ds.x, 4'hc);
    end

    begin
      automatic DisSoftMember dsm = new();
      dsm.override_flag = 1'b0;
      repeat (10) begin
        ok = dsm.randomize();
        `checkd(ok, 1);
        `checkh(dsm.inner.y, 4'h5);
      end
      dsm.override_flag = 1'b1;
      repeat (10) begin
        ok = dsm.randomize();
        `checkd(ok, 1);
        `checkh(dsm.inner.y, 4'hc);
      end
    end

    begin
      automatic DisSoftBothArms dba = new();
      // pick==0: hard a==1 fires (then arm); hoisted disable_soft(a) runs
      dba.pick = 2'd0;
      repeat (10) begin
        ok = dba.randomize();
        `checkd(ok, 1);
        `checkh(dba.a, 4'h1);
        `checkh(dba.b, 4'h8);
      end
      // pick==1: hard b==2 fires (else arm); hoisted disable_soft(b) runs
      dba.pick = 2'd1;
      repeat (10) begin
        ok = dba.randomize();
        `checkd(ok, 1);
        `checkh(dba.b, 4'h2);
        `checkh(dba.a, 4'h7);
      end
    end

    begin
      automatic DisSoftDirect dsd = new();
      automatic bit rFree = 1'b0;
      automatic bit ayFree = 1'b0;
      repeat (16) begin
        ok = dsd.randomize();
        `checkd(ok, 1);
        `checkh(dsd.p, 1'b1);
        `checkh(dsd.q, 7'd9);
        `checkh(dsd.b.y, 4'h4);
        if (dsd.r != 7'd11) rFree = 1'b1;
        if (dsd.a.y != 4'h3) ayFree = 1'b1;
      end
      `checkh(rFree, 1'b1);
      `checkh(ayFree, 1'b1);
    end

    begin
      automatic DisSoftElems dse = new();
      automatic bit fixedFree = 1'b0;
      automatic bit dynFree = 1'b0;
      automatic bit dynWideFree = 1'b0;
      automatic bit midFree = 1'b0;
      automatic bit qFree = 1'b0;
      automatic bit amapFree = 1'b0;
      repeat (16) begin
        ok = dse.randomize();
        `checkd(ok, 1);
        `checkh(dse.fixedArr[1].y, 4'h7);
        `checkh(dse.fixedArr[11].y, 4'h6);
        `checkh(dse.mids[1].inner.y, 4'h5);
        if (dse.mids[10].inner.y != 4'h6) midFree = 1'b1;
        `checkh(dse.q[0].y, 4'h2);
        if (dse.q[2].y != 4'h9) qFree = 1'b1;
        `checkh(dse.amap[-7].y, 4'h8);
        if (dse.amap[7].y != 4'ha) amapFree = 1'b1;
        if (dse.fixedArr[10].y != 4'h5) fixedFree = 1'b1;
        foreach (dse.dynArr[i]) begin
          if (i == 10) begin
            if (dse.dynArr[i].y != 4'h1) dynFree = 1'b1;
          end
          else if (i == 4) begin
            if (dse.dynArr[i].y != 4'h1) dynWideFree = 1'b1;
          end
          else begin
            `checkh(dse.dynArr[i].y, 4'h1);
          end
        end
      end
      `checkh(fixedFree, 1'b1);
      `checkh(dynFree, 1'b1);
      `checkh(dynWideFree, 1'b1);
      `checkh(midFree, 1'b1);
      `checkh(qFree, 1'b1);
      `checkh(amapFree, 1'b1);
    end

    begin
      automatic DisSoftBinder dsb = new();
      automatic bit widened = 1'b0;
      repeat (16) begin
        ok = dsb.randomize();
        `checkd(ok, 1);
        foreach (dsb.objs[i]) begin
          `checkh(dsb.objs[i].y == 4'h1 || dsb.objs[i].y == 4'h2, 1'b1);
          if (dsb.objs[i].y == 4'h2) widened = 1'b1;
        end
      end
      `checkh(widened, 1'b1);
    end


    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
