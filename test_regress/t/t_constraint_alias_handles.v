// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

class Item;
  rand bit [6:0] x;
  rand bit [6:0] arr[2];
  rand bit [6:0] q[$];  // Empty
endclass

// Two rand handles, which may be to one object
class Holder;
  rand Item a;
  rand Item b;
endclass

// The same with class constraints
class ConstrainedHolder;
  rand Item a;
  rand Item b;
  rand bit apart;
  constraint c_x {
    a.x == 7'd22;
    if (apart) b.x == 7'd25;
  }
  constraint c_arr {
    a.arr[0] == 7'd1;
    if (apart) b.arr[0] == 7'd2;
  }
  constraint c_q {foreach (a.q[i]) a.q[i] < 7'd5;}
endclass

// Arrays of each kind, through handles that become one object in a holder used before
class ArrItem;
  rand bit [6:0] f[2];
  rand bit [6:0] d[];
  rand bit [6:0] q[$];
  function new;
    d = new[2];
    q = '{7'd0, 7'd0};
  endfunction
endclass

class FixedHolder;
  rand ArrItem a;
  rand ArrItem b;
  constraint c {
    a.f[1] == 7'd31;
    b.f[1] == 7'd49;
  }
endclass

class DynHolder;
  rand ArrItem a;
  rand ArrItem b;
  constraint c {
    a.d[1] == 7'd31;
    b.d[1] == 7'd49;
  }
endclass

class QueueHolder;
  rand ArrItem a;
  rand ArrItem b;
  constraint c {
    a.q[1] == 7'd31;
    b.q[1] == 7'd49;
  }
endclass

module t;
  Holder holder;
  ConstrainedHolder constrained;
  Item first;
  Item second;
  int ok;
  initial begin
    holder = new;
    first = new;
    second = new;
    // One object: its one x cannot have two values
    holder.a = first;
    holder.b = first;
    ok = holder.randomize() with {
      a.x == 7'd22;
      b.x == 7'd25;
    };
    `checkh(ok, 0);
    // But can have one value through both
    ok = holder.randomize() with {
      a.x == 7'd22;
      b.x > 7'd20;
    };
    `checkh(ok, 1);
    `checkh(first.x, 7'd22);
    // Two objects
    holder.b = second;
    ok = holder.randomize() with {
      a.x == 7'd22;
      b.x == 7'd25;
    };
    `checkh(ok, 1);
    `checkh(first.x, 7'd22);
    `checkh(second.x, 7'd25);
    // An array of one object
    holder.b = first;
    ok = holder.randomize() with {
      a.arr[0] == 7'd1;
      b.arr[0] == 7'd2;
    };
    `checkh(ok, 0);
    ok = holder.randomize() with {
      a.arr[1] == 7'd3;
      b.arr[1] == 7'd3;
    };
    `checkh(ok, 1);
    `checkh(first.arr[1], 7'd3);
    // Class constraints through two handles to one object, and to two
    constrained = new;
    constrained.a = first;
    constrained.b = first;
    ok = constrained.randomize() with {apart == 1'b1;};
    `checkh(ok, 0);
    ok = constrained.randomize();
    `checkh(ok, 1);
    `checkh(constrained.apart, 1'b0);
    `checkh(first.x, 7'd22);
    constrained.b = second;
    ok = constrained.randomize() with {apart == 1'b1;};
    `checkh(ok, 1);
    `checkh(second.x, 7'd25);
    `checkh(second.arr[0], 7'd2);
    // Two handles to one object, then to two, then again to one, the other
    begin
      automatic ArrItem x = new;
      automatic ArrItem y = new;
      automatic FixedHolder fh = new;
      automatic DynHolder dh = new;
      automatic QueueHolder qh = new;
      fh.a = x;
      fh.b = x;
      dh.a = x;
      dh.b = x;
      qh.a = x;
      qh.b = x;
      ok = fh.randomize();
      `checkh(ok, 0);
      ok = dh.randomize();
      `checkh(ok, 0);
      ok = qh.randomize();
      `checkh(ok, 0);
      fh.b = y;
      dh.b = y;
      qh.b = y;
      ok = fh.randomize();
      `checkh(ok, 1);
      `checkh(x.f[1], 7'd31);
      `checkh(y.f[1], 7'd49);
      ok = dh.randomize();
      `checkh(ok, 1);
      `checkh(x.d[1], 7'd31);
      `checkh(y.d[1], 7'd49);
      ok = qh.randomize();
      `checkh(ok, 1);
      `checkh(x.q[1], 7'd31);
      `checkh(y.q[1], 7'd49);
      fh.a = y;
      dh.a = y;
      qh.a = y;
      ok = fh.randomize();
      `checkh(ok, 0);
      ok = dh.randomize();
      `checkh(ok, 0);
      ok = qh.randomize();
      `checkh(ok, 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
