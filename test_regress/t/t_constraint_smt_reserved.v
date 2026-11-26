// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Variables named as solver reserved words or builtin symbols
class Item;
  rand bit [7:0] as;
  rand bit [7:0] true;
  randc bit [3:0] distinct;
  rand bit [7:0] forall;
  rand bit [7:0] STRING;
  rand bit [7:0] _;
  rand bit [7:0] bvadd;
  rand bit [7:0] select;
  rand bit [7:0] \and ;
  constraint c_as {
    as == 8'd5;
    true == as + 1;
  }
  constraint c_soft {soft forall == 8'd9;}
  constraint c_hard {disable soft forall;}
  constraint c_order {
    solve as before true;
    distinct < 4'd8;
  }
  constraint c_dist {STRING dist {8'd3 := 1, 8'd4 := 1};}
  constraint c_symbols {
    _ == 8'd11;
    bvadd == select + 1;
    select == 8'd20;
    \and == _ + 1;
  }
endclass

class Arrays;
  rand bit [7:0] false[2];
  rand bit [7:0] par[$];
  rand bit [7:0] exists[3];
  rand bit [7:0] match[3];
  rand bit HEXADECIMAL;
  rand bit [7:0] NUMERAL[2];
  rand bit [7:0] BINARY[];
  constraint c_false {
    false[0] == 8'd1;
    false[1] == false[0] + 1;
  }
  constraint c_exists {
    if (HEXADECIMAL) unique {exists};
    foreach (exists[i]) exists[i] < 8'd3;
    HEXADECIMAL == 1'b1;
  }
  constraint c_match {
    match.sum() == 8'd6;
    foreach (match[i]) match[i] == 8'd2;
  }
  constraint c_par {
    par.size() == 2;
    foreach (par[i]) par[i] == 8'(i + 4);
  }
  constraint c_binary {
    BINARY.sum() == 8'd4;
    foreach (BINARY[i]) BINARY[i] == 8'd2;
  }
  constraint c_numeral {
    unique {NUMERAL};
    foreach (NUMERAL[i]) NUMERAL[i] < 8'd2;
  }
  function new();
    BINARY = new[2];
  endfunction
endclass

module t;
  Item item;
  Arrays arrays;
  int ok;
  bit [7:0] x;
  initial begin
    item = new;
    arrays = new;
    repeat (8) begin
      ok = item.randomize();
      `checkh(ok, 1);
      `checkh(item.as, 8'd5);
      `checkh(item.true, 8'd6);
      `checkh(item.distinct < 4'd8, 1'b1);
      `checkh(item.STRING == 8'd3 || item.STRING == 8'd4, 1'b1);
      `checkh(item._, 8'd11);
      `checkh(item.bvadd, 8'd21);
      if (item.\and  != 8'd12) `stop;
    end
    item.c_as.constraint_mode(0);
    item.as.rand_mode(0);
    item.as = 8'd7;
    ok = item.randomize() with {true == as + 2;};
    `checkh(ok, 1);
    `checkh(item.true, 8'd9);
    ok = std::randomize(x) with {x == item.as + 1;};
    `checkh(ok, 1);
    `checkh(x, 8'd8);
    ok = arrays.randomize();
    `checkh(ok, 1);
    `checkh(arrays.false[0], 8'd1);
    `checkh(arrays.false[1], 8'd2);
    `checkh(arrays.par.size(), 2);
    `checkh(arrays.par[0], 8'd4);
    `checkh(arrays.par[1], 8'd5);
    `checkh(arrays.exists[0] + arrays.exists[1] + arrays.exists[2], 8'd3);
    `checkh(arrays.exists[0] != arrays.exists[1], 1'b1);
    `checkh(arrays.match[0] + arrays.match[1] + arrays.match[2], 8'd6);
    `checkh(arrays.NUMERAL[0] != arrays.NUMERAL[1], 1'b1);
    `checkh(arrays.BINARY[0] + arrays.BINARY[1], 8'd4);
    arrays.c_par.constraint_mode(0);
    ok = arrays.randomize() with {
      par.size() == 3;
      foreach (par[i]) par[i] == 8'(i + 4);
    };
    `checkh(ok, 1);
    `checkh(arrays.par.size(), 3);
    `checkh(arrays.par[2], 8'd6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
