// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Elem;
  rand bit [6:0] v;
endclass

// Constraints on the members of each element
class Elems;
  rand Elem q[$];
  constraint c_v {foreach (q[i]) q[i].v == 7'd6;}
  function new;
    Elem e;
    repeat (2) begin
      e = new;
      q.push_back(e);
    end
  endfunction
endclass

// Also sizing the array
class SizedElems;
  rand Elem q[$];
  constraint c_v {foreach (q[i]) q[i].v == 7'd6;}
  constraint c_size {q.size() == 3;}
  function new;
    Elem e;
    repeat (2) begin
      e = new;
      q.push_back(e);
    end
  endfunction
endclass

// A guard keeps null elements out
class GuardedElems;
  rand Elem q[$];
  constraint c_v {foreach (q[i]) if (q[i] != null) q[i].v == 7'd6;}
  function new;
    Elem e;
    e = new;
    q.push_back(e);
    q.push_back(null);
  endfunction
endclass

// A member of a null rand handle
class Holder;
  rand Elem h;
  constraint c_v {h.v == 7'd3;}
endclass

// Another array, resized in the same call
class ElemsAndValues;
  rand Elem q[$];
  rand bit [6:0] values[$];
  constraint c_v {foreach (q[i]) q[i].v == 7'd6;}
  function new;
    Elem e;
    e = new;
    q.push_back(e);
    values = '{31, 57, 19};
  endfunction
endclass

// A guard false at run time keeps the constraint out
class OffElems;
  rand Elem q[$];
  bit active;
  constraint c_v {foreach (q[i]) if (active) q[i].v == 7'd42;}
  function new;
    Elem e;
    e = new;
    q.push_back(e);
    q.push_back(null);
  endfunction
endclass

module t;
  initial begin
    int ok;
    begin
      // Test: growing the array adds null elements, whose constrained members are an error
      automatic Elems elems = new;
      ok = elems.randomize() with {q.size() == 3;};
      `checkd(ok, 0);
      `checkd(elems.q.size(), 2);
    end
    begin
      // Test: not growing it is fine
      automatic Elems elems = new;
      ok = elems.randomize() with {q.size() == 1;};
      `checkd(ok, 1);
      `checkd(elems.q.size(), 1);
      `checkd(elems.q[0].v, 6);
    end
    begin
      // Test: a null element already in the array
      automatic Elems elems = new;
      elems.q.push_back(null);
      ok = elems.randomize();
      `checkd(ok, 0);
      `checkd(elems.q.size(), 3);
    end
    begin
      // Test: the class constraints size it
      automatic SizedElems sized = new;
      ok = sized.randomize();
      `checkd(ok, 0);
      `checkd(sized.q.size(), 2);
    end
    begin
      automatic GuardedElems guarded = new;
      ok = guarded.randomize();
      `checkd(ok, 1);
      `checkd(guarded.q[0].v, 6);
    end
    begin
      // Test: a member of a null rand handle
      automatic Holder holder = new;
      ok = holder.randomize();
      `checkd(ok, 0);
      holder.h = new;
      ok = holder.randomize();
      `checkd(ok, 1);
      `checkd(holder.h.v, 3);
    end
    begin
      // Test: the arrays a failed call resized keep their elements
      automatic ElemsAndValues ev = new;
      ok = ev.randomize() with {q.size() == 2; values.size() == 1;};
      `checkd(ok, 0);
      `checkd(ev.q.size(), 1);
      `checkd(ev.values.size(), 3);
      `checkd(ev.values[0], 31);
      `checkd(ev.values[1], 57);
      `checkd(ev.values[2], 19);
    end
    begin
      automatic OffElems off = new;
      off.active = 0;
      ok = off.randomize();
      `checkd(ok, 1);
      off.active = 1;
      ok = off.randomize();
      `checkd(ok, 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
