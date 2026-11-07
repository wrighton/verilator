// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A rand class handle compared in a constraint guard is state; only the rand
// members of the object it refers to are solved (IEEE 1800-2023 18.5.12)
class Sub;
  rand int x;
endclass

class Holder;
  rand int y;
  rand Sub s;
  constraint c_y {y inside {[0 : 100]};}
  constraint c_member {if (s != null) s.x > y;}
endclass

class NullGuard;
  rand int y;
  rand Sub s;
  constraint c {
    (s == null) -> y == 9;
    (s != null) -> y == 5;
  }
endclass

class FuncArg;
  rand int y;
  rand Sub s;
  function int pick(Sub h);
    return h == null ? 9 : 5;
  endfunction
  constraint c {y == pick(s);}
endclass

// Narrow no-mode reproducer: eliminating the guarded constraint must also eliminate
// its reference to the unregistered member, not leave an SMT implication naming it.
class PlainItem;
  rand bit [6:0] w;
endclass

class PlainSeq;
  rand PlainItem item;
  rand bit [6:0] low;
  constraint c {if (item != null) item.w == low;}
endclass

class GuardItem;
  rand bit [6:0] w;
endclass

class GuardSeq;
  rand GuardItem item;
  rand bit [6:0] low;
  rand bit pick;
  bit enabled;
  constraint c {
    if (item != null) item.w == low;
    if (enabled && (item != null)) item.w == low;
    // The state part can sift out the constraint regardless of its operand order.
    if (pick && (item != null)) item.w == 7'd23;
    if ((item != null) && pick) item.w == 7'd23;
    if (!((item == null) || !pick)) item.w == 7'd23;
    if ((item == null) || pick)
    low == 7'd23;
    else
    low == 7'd17;
    if (((item == null) || pick) && (enabled || pick)) low == 7'd23;
    if (((item != null) && pick) || (enabled && pick)) low == 7'd23;
    // A false/true state operand also sifts out a potentially invalid random member read.
    if ((item.w == 7'd23) && (item != null)) low == 7'd23;
    if ((item.w == 7'd23) || (item == null)) low == 7'd23;
    (item != null) -> item.w == low;
    // A state guard nested inside a solver-dependent conditional.
    if (pick) {if (item != null) item.w == low;}
  }
endclass

class StateItem;
  bit flag;
endclass

class StateGuards;
  StateItem item;
  bit select_item;
  rand bit [6:0] value;
  constraint c {
    if ((item.flag == 1) && (item != null)) value == 7'd23;
    if ((item != null) && (item.flag == 1)) value == 7'd23;
    if ((item.flag == 1) || (item == null)) value == 7'd23;
    if ((item == null) || (item.flag == 1)) value == 7'd23;
    if (!((item.flag == 1) && (item != null))) value != 7'd17;
    if ((select_item ? item.flag : 1'b1) == 1'b1) value == 7'd23;
  }
endclass

class UnsiftedError;
  StateItem item;
  rand bit [6:0] value;
  rand bit pick;
  constraint c {if ((item.flag == 1) && pick) value == 7'd23;}
endclass

class PartialStateGuard;
  StateItem item;
  rand bit pick;
  rand bit [6:0] value;
  constraint c {
    if (((item.flag == 1) && (item != null)) || pick)
    value == 7'd23;
    else
    value == 7'd9;
    if (pick && !((item.flag == 1) && (item != null))) value == 7'd23;
  }
endclass

class PartialRandGuard;
  rand GuardItem item;
  rand bit pick;
  rand bit [6:0] value;
  constraint c {
    if (((item.w == 1) && (item != null)) || pick)
    value == 7'd23;
    else
    value == 7'd9;
    if (pick && !((item.w == 1) && (item != null))) value == 7'd23;
  }
endclass

class PartialPlainGuard;
  rand PlainItem item;
  rand bit pick;
  rand bit [6:0] value;
  constraint c {
    if (((item.w == 1) && (item != null)) || pick)
    value == 7'd23;
    else
    value == 7'd9;
  }
endclass

package GuardFunctions;
  bit enabled;
  // A read-only package function need not be assumed pure merely because it is legal.
  function int read_enabled();
    int result;
    result = int'(enabled);
    return result;
  endfunction
endpackage

class StaticGuard;
  rand bit [6:0] value;
  constraint c {
    if (GuardFunctions::read_enabled() != 0)
    value == 7'd23;
    else
    value == 7'd9;
  }
endclass

class NestedItemError;
  StateItem item;
  rand bit pick;
  rand bit [6:0] value;
  constraint c {
    if (pick) {
      if (item.flag == 1) value == 7'd23;
    }
  }
endclass

class InactiveItemError;
  StateItem item;
  bit active;
  rand bit [6:0] value;
  constraint c {
    if (active) {
      if (item.flag == 1) value == 7'd23;
    }
  }
endclass

class NegatedItemError;
  StateItem item;
  rand bit [6:0] value;
  // -> is also a binary logical operator (IEEE 1800-2023 11.4.7, A.8.6).
  constraint c {!((item.flag == 1) -> (value == 7'd23));}
endclass

class SoftItemError;
  StateItem item;
  rand bit [6:0] value;
  constraint c {if (item.flag == 1) soft value == 7'd23;}
endclass

class SoftNegatedItemError;
  StateItem item;
  rand bit [6:0] value;
  constraint c {soft !((item.flag == 1) -> (value == 7'd23));}
endclass

module t;
  initial begin
    int res;

    begin
      automatic Holder h = new;
      h.s = new;
      repeat (10) begin
        res = h.randomize();
        `checkd(res, 1);
        `checkd(h.s.x > h.y, 1);
      end
    end

    begin
      automatic NullGuard g = new;
      res = g.randomize();
      `checkd(res, 1);
      `checkd(g.y, 9);
      g.s = new;
      res = g.randomize();
      `checkd(res, 1);
      `checkd(g.y, 5);
    end

    begin
      automatic FuncArg f = new;
      res = f.randomize();
      `checkd(res, 1);
      `checkd(f.y, 9);
      f.s = new;
      res = f.randomize();
      `checkd(res, 1);
      `checkd(f.y, 5);
    end

    begin
      automatic PlainSeq s = new;
      automatic PlainItem saved = new;
      s.item = saved;
      for (int i = 0; i < 10; ++i) begin
        res = s.randomize() with {low == 7'(i);};
        `checkd(res, 1);
        `checkd(s.item.w, 7'(i));
        saved.w = 7'd99;
        s.item = null;
        res = s.randomize();
        `checkd(res, 1);
        `checkd(s.item == null, 1);
        `checkd(saved.w, 7'd99);
        res = s.randomize() with {if (item != null) item.w == low;};
        `checkd(res, 1);
        `checkd(saved.w, 7'd99);
        s.item = saved;
      end
    end

    begin
      automatic GuardSeq s = new;
      automatic GuardItem saved = new;
      s.item = saved;
      // The setter is legal: the handle is nonnull here, then cleared before randomize().
      s.item.w.rand_mode(1);
      for (int i = 0; i < 10; ++i) begin
        s.enabled = 1'(i);
        res = s.randomize() with {pick == 1'(i);};
        `checkd(res, 1);
        `checkd(s.low, i[0] ? 7'd23 : 7'd17);
        `checkd(s.item.w, s.low);
        `checkd(s.item == saved, 1);
        saved.w = 7'd99;
        s.item = null;
        res = s.randomize();
        `checkd(res, 1);
        `checkd(s.low, 7'd23);
        `checkd(saved.w, 7'd99);
        res = s.randomize() with {pick == 1'(i);};
        `checkd(res, 1);
        `checkd(s.low, 7'd23);
        `checkd(s.item == null, 1);
        `checkd(saved.w, 7'd99);
        res = s.randomize() with {
          if (item != null) item.w == low;
          (item != null) -> item.w == low;
        };
        `checkd(res, 1);
        `checkd(saved.w, 7'd99);
        s.item = saved;
      end
    end

    begin
      automatic StateGuards s = new;
      automatic StateItem saved = new;
      for (int i = 0; i < 10; ++i) begin
        s.item = null;
        s.select_item = 0;
        res = s.randomize();
        `checkd(res, 1);
        `checkd(s.value, 7'd23);
        s.select_item = 1;
        res = s.randomize();
        `checkd(res, 0);
        s.item = saved;
        saved.flag = 1'(i);
        res = s.randomize() with {value == (1'(i) ? 7'd23 : 7'd9);};
        `checkd(res, 1);
        `checkd(s.value, i[0] ? 7'd23 : 7'd9);
        `checkd(saved.flag, 1'(i));
      end
    end

    begin
      automatic UnsiftedError e = new;
      // ERROR && RANDOM is ERROR, even though the solver could choose pick == 0.
      res = e.randomize();
      `checkd(res, 0);
      e.item = new;
      e.item.flag = 0;
      res = e.randomize() with {value == 7'd9;};
      `checkd(res, 1);
      e.item.flag = 1;
      res = e.randomize() with {
        pick == 1;
        value == 7'd23;
      };
      `checkd(res, 1);
    end

    begin
      automatic PartialStateGuard s = new;
      automatic PartialRandGuard r = new;
      automatic PartialPlainGuard p = new;
      automatic GuardItem saved = new;
      r.item = saved;
      r.item.w.rand_mode(1);
      r.item = null;
      for (int i = 0; i < 10; ++i) begin
        res = s.randomize() with {pick == 1'(i);};
        `checkd(res, 1);
        `checkd(s.value, i[0] ? 7'd23 : 7'd9);
        res = r.randomize() with {pick == 1'(i);};
        `checkd(res, 1);
        `checkd(r.value, i[0] ? 7'd23 : 7'd9);
        res = p.randomize() with {pick == 1'(i);};
        `checkd(res, 1);
        `checkd(p.value, i[0] ? 7'd23 : 7'd9);
      end
    end

    begin
      automatic StaticGuard s = new;
      for (int i = 0; i < 10; ++i) begin
        GuardFunctions::enabled = 1'(i);
        res = s.randomize();
        `checkd(res, 1);
        `checkd(s.value, i[0] ? 7'd23 : 7'd9);
        res = s.randomize() with {
          if (GuardFunctions::read_enabled() != 0)
          value == 7'd23;
          else
          value == 7'd9;
        };
        `checkd(res, 1);
      end
    end

    begin
      automatic NestedItemError n = new;
      automatic InactiveItemError inactive = new;
      automatic NegatedItemError neg = new;
      automatic SoftItemError soft_guard = new;
      automatic SoftNegatedItemError soft_neg = new;
      for (int i = 0; i < 4; ++i) begin
        // A RANDOM outer predicate cannot hide ERROR by the solver choosing pick == 0.
        res = n.randomize();
        `checkd(res, 0);
        res = n.randomize() with {pick == 1'(i);};
        `checkd(res, 0);
        inactive.active = 0;
        res = inactive.randomize();
        `checkd(res, 1);
        inactive.active = 1;
        res = inactive.randomize();
        `checkd(res, 0);
        res = neg.randomize();
        `checkd(res, 0);
        res = soft_guard.randomize();
        `checkd(res, 0);
        res = soft_neg.randomize();
        `checkd(res, 0);
      end
      // Status is local to an item/call; restoration must not retain the prior ERROR.
      n.item = new;
      n.item.flag = 1;
      res = n.randomize() with {pick == 1;};
      `checkd(res, 1);
      `checkd(n.value, 7'd23);
      neg.item = new;
      neg.item.flag = 1;
      res = neg.randomize();
      `checkd(res, 1);
      `checkd(neg.value != 7'd23, 1);
      soft_guard.item = new;
      soft_guard.item.flag = 1;
      res = soft_guard.randomize();
      `checkd(res, 1);
      `checkd(soft_guard.value, 7'd23);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
