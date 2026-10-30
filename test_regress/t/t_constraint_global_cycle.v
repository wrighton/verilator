// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Classes with rand handles to each other (IEEE 1800-2023 18.4)

typedef class Ring2;

class Ring;
  rand bit [6:0] b[];
  rand Ring2 next;
  int post_count;
  function void post_randomize();
    ++post_count;
  endfunction
  constraint c_b {foreach (b[i]) b[i] < 7'd3;}
  function new();
    b = new[2];
  endfunction
endclass

class Ring2;
  rand bit [14:0] x;
  rand Ring next;
endclass

// A cycle not through the randomized class: Top -> A -> B -> A, and B -> C -> D -> C
typedef class CycB;
typedef class CycD;

class CycA;
  rand bit [6:0] va;
  rand CycB b;
  constraint c_a {va > 7'd120;}
endclass

class CycC;
  rand bit [6:0] vc;
  rand CycD d;
  constraint c_c {vc < 7'd3;}
endclass

class CycB;
  rand CycA a;
  rand CycC c;
endclass

class CycD;
  rand CycC c;
endclass

class Top;
  rand CycA a;
  function new();
    a = new;
    a.b = new;
    a.b.c = new;
  endfunction
endclass

// A cycle through a derived class
typedef class CycX;

class CycBase;
  rand bit [6:0] vb;
  constraint c_vb {vb < 7'd3;}
endclass

class CycDerived extends CycBase;
  rand CycX x;
endclass

class CycX;
  rand CycBase c;
endclass

module t;
  initial begin
    automatic Ring ring = new;
    automatic Ring2 r2 = new;
    automatic Ring ring2 = new;
    automatic Top tp = new;
    int randomize_result;
    // Without the second object
    repeat (5) begin
      randomize_result = ring.randomize();
      `checkd(randomize_result, 1);
      foreach (ring.b[i]) `checkd(ring.b[i] < 7'd3, 1'b1);
    end
    // Objects of the same class at two levels, each with its constraints
    ring.next = r2;
    r2.next = ring2;
    repeat (5) begin
      randomize_result = ring.randomize();
      `checkd(randomize_result, 1);
      foreach (ring.b[i]) `checkd(ring.b[i] < 7'd3, 1'b1);
      foreach (ring2.b[i]) `checkd(ring2.b[i] < 7'd3, 1'b1);
    end
    randomize_result = r2.randomize();
    `checkd(randomize_result, 1);
    foreach (ring2.b[i]) `checkd(ring2.b[i] < 7'd3, 1'b1);
    // The objects form a cycle: each is randomized once per call
    r2.next = ring;
    repeat (5) begin
      automatic int count = ring.post_count;
      ring.b[0] = 7'd100;
      randomize_result = ring.randomize();
      `checkd(randomize_result, 1);
      foreach (ring.b[i]) `checkd(ring.b[i] < 7'd3, 1'b1);
      `checkd(ring.post_count, count + 1);
      ring.b[0] = 7'd100;
      randomize_result = ring.randomize() with {b[1] == 7'd1;};
      `checkd(randomize_result, 1);
      `checkd(ring.b[0] < 7'd3, 1'b1);
      `checkd(ring.b[1], 7'd1);
      `checkd(ring.post_count, count + 2);
      ring.b[0] = 7'd100;
      randomize_result = r2.randomize();
      `checkd(randomize_result, 1);
      foreach (ring.b[i]) `checkd(ring.b[i] < 7'd3, 1'b1);
    end
    // Cycles through other classes
    repeat (5) begin
      randomize_result = tp.randomize();
      `checkd(randomize_result, 1);
      `checkd(tp.a.va > 7'd120, 1'b1);
      `checkd(tp.a.b.c.vc < 7'd3, 1'b1);
    end
    begin
      automatic CycX cx = new;
      automatic CycDerived cd = new;
      cx.c = cd;
      cd.x = cx;
      repeat (5) begin
        cd.vb = 7'd100;
        randomize_result = cx.randomize();
        `checkd(randomize_result, 1);
        `checkd(cd.vb < 7'd3, 1'b1);
        cd.vb = 7'd100;
        randomize_result = cd.randomize();
        `checkd(randomize_result, 1);
        `checkd(cd.vb < 7'd3, 1'b1);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
