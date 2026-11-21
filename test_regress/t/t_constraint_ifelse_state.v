// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// if / else-if constraints whose conditions call functions of non-rand objects

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef enum int {NORTH, SOUTH, EAST, WEST} dir_e;

class Coord;
  rand int unsigned x;
  rand int unsigned y;
  function bit is_west_edge();
    return x == 1;
  endfunction
  function bit is_east_edge();
    return x == 4;
  endfunction
endclass

class Ep;
  rand dir_e dir;
  rand Coord coord;
  function new();
    coord = new;
  endfunction
endclass

// Only state values in the if / else-if (non-rand handles)
class Path;
  Coord rtr;
  Ep init;
  Ep tgt;
  rand int unsigned other;
  function new();
    rtr = new;
    init = new;
    tgt = new;
  endfunction
  constraint c_rng { other < 10; }
  constraint c_dep {
    if (!rtr.is_west_edge() && (init.dir == WEST)) {
      if (tgt.dir inside {NORTH, SOUTH}) { tgt.coord.x >= rtr.x; }
    }
    else if (!rtr.is_east_edge() && (init.dir == EAST)) {
      if (tgt.dir inside {NORTH, SOUTH}) { tgt.coord.x <= rtr.x; }
    }
  }
endclass

// State conditions selecting constraints on rand members
class Item;
  Coord cfg;
  rand int unsigned a;
  rand int unsigned b;
  function new();
    cfg = new;
  endfunction
  constraint c_a {
    if (cfg.is_west_edge()) { a < 5; }
    else if (cfg.is_east_edge()) { a inside {[10:12]}; }
    else { a == 100; }
  }
  constraint c_b {
    soft b == 7;
    if (cfg.is_west_edge()) { soft b == 3; }
    else if (cfg.is_east_edge()) { soft b == 4; }
  }
endclass

module t;
  initial begin
    automatic Path p = new;
    automatic Item it = new;
    automatic int randomize_result;

    p.rtr.x = 2;
    p.init.dir = WEST;
    p.tgt.dir = NORTH;
    p.tgt.coord.x = 3;
    randomize_result = p.randomize();
    `checkd(randomize_result, 1);
    `checkd(p.other < 10, 1);
    p.tgt.coord.x = 1;  // Violates the WEST rule
    randomize_result = p.randomize();
    `checkd(randomize_result, 0);
    p.init.dir = EAST;  // Satisfies the EAST rule
    randomize_result = p.randomize();
    `checkd(randomize_result, 1);
    p.rtr.x = 4;  // East edge: no rule
    p.tgt.coord.x = 9;
    randomize_result = p.randomize();
    `checkd(randomize_result, 1);

    it.cfg.x = 1;
    repeat (5) begin
      randomize_result = it.randomize();
      `checkd(randomize_result, 1);
      `checkd(it.a < 5, 1);
      `checkd(it.b, 3);
    end
    it.cfg.x = 4;
    repeat (5) begin
      randomize_result = it.randomize();
      `checkd(randomize_result, 1);
      `checkd(it.a >= 10 && it.a <= 12, 1);
      `checkd(it.b, 4);
      randomize_result = it.randomize() with {
        if (cfg.is_west_edge()) { a == 0; }
        else if (cfg.is_east_edge()) { a == 11; }
      };
      `checkd(randomize_result, 1);
      `checkd(it.a, 11);
    end
    it.cfg.x = 3;
    randomize_result = it.randomize();
    `checkd(randomize_result, 1);
    `checkd(it.a, 100);
    `checkd(it.b, 7);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
