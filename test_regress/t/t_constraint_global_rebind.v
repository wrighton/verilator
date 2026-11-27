// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The objects of rand base class handles, whose constraints are set up when solved with the
// holder's (IEEE 1800-2023 18.5.2, 18.5.9), swapped between the handles from one randomize()
// to the next: the objects' variables are named by the handles holding them in each solve,
// also after a solve in which both handles held one object

class Leaf;
  rand bit [7:0] v;
endclass

class Keyed extends Leaf;
  bit [7:0] key;
  constraint c {v == key;}
  function new(bit [7:0] key);
    this.key = key;
  endfunction
endclass

class Mid;
  rand Leaf one;
endclass

// Its constraint reads the members of the objects through the handles, as the objects'
// constraints do through their own names
class Top;
  rand Mid m, n;
  constraint c {m.one.v != n.one.v;}
  function new();
    m = new;
    n = new;
  endfunction
endclass

class Pair;
  rand Leaf h1, h2;
  constraint c {h1.v != h2.v;}
endclass

module t;
  initial begin
    automatic Top t = new;
    automatic Keyed a = new(8'h11);
    automatic Keyed b = new(8'h22);
    automatic int randomize_result;
    for (int round = 0; round < 4; ++round) begin
      t.m.one = round[0] ? b : a;
      t.n.one = round[0] ? a : b;
      randomize_result = t.randomize();
      `checkh(randomize_result, 1);
      `checkh(a.v, 8'h11);
      `checkh(b.v, 8'h22);
    end
    begin
      automatic Pair p = new;
      automatic Keyed c = new(8'h33);
      automatic Keyed a2 = new(8'h11);  // Of the key of a
      for (int round = 0; round < 2; ++round) begin
        // One object for both, which cannot differ from itself
        p.h1 = a;
        p.h2 = a;
        randomize_result = p.randomize();
        `checkh(randomize_result, 0);
        p.h1 = round[0] ? c : a;
        p.h2 = round[0] ? a : c;
        randomize_result = p.randomize();
        `checkh(randomize_result, 1);
        `checkh(a.v, 8'h11);
        `checkh(c.v, 8'h33);
        p.h1 = a;
        p.h2 = a;
        randomize_result = p.randomize();
        `checkh(randomize_result, 0);
        // Objects of one key, whose constraints cannot hold together
        p.h2 = a2;
        randomize_result = p.randomize();
        `checkh(randomize_result, 0);
        `checkh(a.v, 8'h11);
        `checkh(a2.v, 8'h00);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
