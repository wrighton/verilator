// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Objects reached through interface class handles: their random number generator, their
// randomization as rand members, and choosing between objects of two implementing classes

interface class Root;
  pure virtual function int val();
endclass

interface class Child extends Root;
  pure virtual function int other();
endclass

interface class Sibling;
  pure virtual function int marker();
endclass

// Implementing Root also through Child in Derived
class Base implements Root;
  rand bit [6:0] x;
  int pre_count;
  int post_count;
  constraint c_x {x inside {[7'd5 : 7'd29]};}
  virtual function int val();
    return int'(x);
  endfunction
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class Derived extends Base implements Child, Sibling;
  rand bit [6:0] y;
  constraint c_y {y == x + 7'd63;}
  virtual function int other();
    return int'(y);
  endfunction
  virtual function int marker();
    return 1;
  endfunction
endclass

class Other implements Child, Sibling;
  rand bit [6:0] v;
  constraint c_v {v inside {[7'd70 : 7'd96]};}
  virtual function int val();
    return int'(v);
  endfunction
  virtual function int other();
    return 51;
  endfunction
  virtual function int marker();
    return 2;
  endfunction
endclass

class Holder;
  rand Child a;
endclass

module t;
  initial begin
    automatic Derived d = new;
    automatic Derived twin = new;
    automatic Other o = new;
    automatic Holder h = new;
    automatic Root r = d;
    automatic Child c;
    automatic Sibling s = d;
    automatic int randomize_result;
    automatic bit [6:0] x;

    // srandom() through an interface class handle seeds the object's generator
    r.srandom(7);
    twin.srandom(7);
    randomize_result = d.randomize();
    `checkd(randomize_result, 1);
    randomize_result = twin.randomize();
    `checkd(randomize_result, 1);
    `checkd(d.x, twin.x);
    s.srandom(9);
    twin.srandom(9);
    randomize_result = d.randomize();
    `checkd(randomize_result, 1);
    randomize_result = twin.randomize();
    `checkd(randomize_result, 1);
    `checkd(d.y, twin.y);

    // A rand interface class handle: its object is randomized with its constraints and
    // callbacks
    d.pre_count = 0;
    d.post_count = 0;
    for (int i = 0; i < 6; ++i) begin
      // Choosing between objects of two classes implementing the handle's class
      if (i % 2 == 0) c = d;
      else c = o;
      h.a = c;
      randomize_result = h.randomize();
      `checkd(randomize_result, 1);
      if (i % 2 == 0) begin
        `checkd(d.x inside {[7'd5 : 7'd29]}, 1'b1);
        `checkd(d.y, d.x + 7'd63);
        `checkd(c.other(), int'(d.y));
      end
      else begin
        `checkd(o.v inside {[7'd70 : 7'd96]}, 1'b1);
        `checkd(c.val(), int'(o.v));
      end
    end
    `checkd(d.pre_count, 3);
    `checkd(d.post_count, 3);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
