// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Rand member objects of classes that only share a base class (as all UVM classes
// share uvm_object) do not form a cycle of rand handles: each member object is solved
// together with the container (IEEE 1800-2023 18.4), and its pre_randomize() runs
// once (18.6.2)

class Base;
endclass

class Coord extends Base;
  rand bit [7:0] x;
  constraint c_x {x < 8'd100;}
endclass

class Requestor extends Base;
  rand bit is_target;
  rand Coord coord;
  int pre_count;
  int post_count;
  constraint c_type {is_target -> coord.x > 8'd50;}
  function new();
    coord = new;
  endfunction
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class Cfg extends Base;
  rand Requestor init;
  rand Requestor tgt;
  rand bit [3:0] vc;
  rand bit [3:0] slice;
  constraint c_types {
    !init.is_target;
    tgt.is_target;
  }
  constraint c_coords {
    init.coord.x == 8'd7;
    tgt.coord.x == {vc, slice};
  }
  function new();
    init = new;
    tgt = new;
  endfunction
endclass

module t;
  initial begin
    automatic Cfg cfg = new;
    int randomize_result;
    repeat (10) begin
      automatic int init_pre = cfg.init.pre_count;
      automatic int tgt_post = cfg.tgt.post_count;
      randomize_result = cfg.randomize();
      `checkd(randomize_result, 1);
      `checkd(cfg.init.pre_count, init_pre + 1);
      `checkd(cfg.tgt.post_count, tgt_post + 1);
      `checkd(cfg.init.is_target, 1'b0);
      `checkd(cfg.tgt.is_target, 1'b1);
      `checkd(cfg.init.coord.x, 8'd7);
      `checkd(cfg.tgt.coord.x, {cfg.vc, cfg.slice});
      `checkd(cfg.tgt.coord.x > 8'd50 && cfg.tgt.coord.x < 8'd100, 1'b1);
    end
    // The values of rand_mode(0) members are kept and used as state
    cfg.vc.rand_mode(0);
    cfg.slice.rand_mode(0);
    cfg.vc = 4'd4;
    cfg.slice = 4'd9;
    repeat (5) begin
      randomize_result = cfg.randomize();
      `checkd(randomize_result, 1);
      `checkd(cfg.vc, 4'd4);
      `checkd(cfg.slice, 4'd9);
      `checkd(cfg.tgt.coord.x, 8'h49);
      `checkd(cfg.init.coord.x, 8'd7);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
