// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Classes of rand handles in rand unpacked structs forming a cycle of types: a class holding
// a struct with a handle of its own class, and two classes holding each other's through
// structs, one in an array of structs, randomized through a container or alone. Verilation
// ends (the test's timeout and memory bound), and so does randomization: of objects acyclic
// with the inner handles null, and of rings of objects, as an object being randomized is not
// randomized again (IEEE 1800-2023 18.4 does not forbid such rings).

typedef class N;
typedef class C1;
typedef class C2;
typedef struct {
  rand N h;
  rand bit [3:0] k;
} SN;
typedef struct {
  rand C2 h;
  rand bit [3:0] k;
} S1;
typedef struct {
  rand C1 h;
  rand bit [3:0] k;
} S2;

class N;
  rand bit [3:0] x;
  rand SN s;
  int pre_count;
  int post_count;
  constraint c_n {x[0] == 1'b1;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class C1;
  rand bit [3:0] x;
  rand S1 s;
  int pre_count;
  bit block;  // Fails randomize()
  constraint c_1 {
    x > 4'd10;
    !block;
  }
  function void pre_randomize();
    ++pre_count;
  endfunction
endclass

class C2;
  rand bit [3:0] y;
  rand S2 s[2];
  int pre_count;
  constraint c_2 {y < 4'd4;}
  function void pre_randomize();
    ++pre_count;
  endfunction
endclass

// A ring through a struct and a rand class handle, each object's callbacks called once per
// call, also by randomize() with
typedef class MB;
typedef struct {rand MB h;} SM;
class MA;
  rand bit [6:0] x;
  rand SM s;
  int pre_count;
  int post_count;
  constraint c_ma {x < 7'd100;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass
class MB;
  rand bit [6:0] y;
  rand MA a;
  int pre_count;
  int post_count;
  constraint c_mb {y > 7'd5;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

// The container randomizes, through structs only, a chain of each
class H;
  rand SN sn;
  rand S1 s1;
  function new();
    sn.h = new;
    sn.h.s.h = new;  // Its inner handle stays null
    s1.h = new;
    s1.h.s[1].h = new;  // Its inner handle stays null
  endfunction
endclass

module t;
  initial begin
    automatic H h = new;
    automatic H hr = new;  // Its objects in rings, reached through the container
    automatic N n = new;
    automatic N self = new;
    automatic C1 a = new;
    automatic C2 b = new;
    automatic MA ma = new;
    automatic MB mb = new;
    automatic int ok;
    self.s.h = self;
    hr.sn.h.s.h = hr.sn.h;
    hr.s1.h.s[1].h.s.h = hr.s1.h;
    a.s.h = b;
    b.s[1].h = a;
    for (int call = 1; call <= 10; ++call) begin
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.sn.h.pre_count, call);
      `checkd(h.sn.h.post_count, call);
      `checkd(h.sn.h.x[0], 1'b1);
      `checkd(h.sn.h.s.h.pre_count, call);
      `checkd(h.sn.h.s.h.x[0], 1'b1);
      `checkd(h.sn.h.s.h.s.h, null);
      `checkd(h.s1.h.pre_count, call);
      `checkd(h.s1.h.y < 4'd4, 1'b1);
      `checkd(h.s1.h.s[0].h, null);
      `checkd(h.s1.h.s[1].h.pre_count, call);
      `checkd(h.s1.h.s[1].h.x > 4'd10, 1'b1);
      `checkd(h.s1.h.s[1].h.s.h, null);
      // The class of the cycle randomized alone
      ok = n.randomize();
      `checkd(ok, 1);
      `checkd(n.pre_count, call);
      `checkd(n.x[0], 1'b1);
      ok = hr.randomize();
      `checkd(ok, 1);
      `checkd(hr.sn.h.pre_count, call);
      `checkd(hr.sn.h.post_count, call);
      `checkd(hr.sn.h.x[0], 1'b1);
      `checkd(hr.s1.h.pre_count, call);
      `checkd(hr.s1.h.s[1].h.pre_count, call);
      `checkd(hr.s1.h.s[1].h.x > 4'd10, 1'b1);
      // Rings of objects: each randomized once per call
      ok = self.randomize();
      `checkd(ok, 1);
      `checkd(self.pre_count, call);
      `checkd(self.post_count, call);
      `checkd(self.x[0], 1'b1);
      ok = a.randomize();
      `checkd(ok, 1);
      `checkd(a.pre_count, call);
      `checkd(b.pre_count, call);
      `checkd(a.x > 4'd10, 1'b1);
      `checkd(b.y < 4'd4, 1'b1);
    end
    // The ring through a struct and a handle, from each object, plain and with constraints
    ma.s.h = mb;
    mb.a = ma;
    for (int start = 0; start < 4; ++start) begin
      ma.pre_count = 0;
      ma.post_count = 0;
      mb.pre_count = 0;
      mb.post_count = 0;
      case (start)
        0: ok = ma.randomize();
        1: ok = ma.randomize() with {x < 7'd50;};
        2: ok = mb.randomize();
        default: ok = mb.randomize() with {y < 7'd50;};
      endcase
      `checkd(ok, 1);
      `checkd(ma.pre_count, 1);
      `checkd(ma.post_count, 1);
      `checkd(mb.pre_count, 1);
      `checkd(mb.post_count, 1);
      `checkd(ma.x < 7'd100, 1'b1);
      `checkd(mb.y > 7'd5, 1'b1);
      if (start == 1) `checkd(ma.x < 7'd50, 1'b1);
      if (start == 3) `checkd(mb.y < 7'd50, 1'b1);
    end
    // A failed randomize() of an object of a ring leaves it to be randomized through the ring
    a.block = 1'b1;
    ok = a.randomize();
    `checkd(ok, 0);
    a.block = 1'b0;
    a.pre_count = 0;
    ok = b.randomize();
    `checkd(ok, 1);
    `checkd(a.pre_count, 1);
    `checkd(a.x > 4'd10, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
