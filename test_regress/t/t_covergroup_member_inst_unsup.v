// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A covergroup instance with a clocking event held in a class member is not sampled on the event

module t;
  logic clk;
  logic [1:0] st;

  covergroup cg @(posedge clk);
    cp: coverpoint st;
  endgroup

  class Holder;
    cg inst;
    static cg shared = new;  // Sampled like a module-level instance
    function new();
      inst = new;
    endfunction
  endclass

  Holder h = new;
endmodule
