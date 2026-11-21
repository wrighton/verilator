// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Each object's pre_randomize/post_randomize runs once per randomize() call
// (IEEE 1800-2023 18.6.2, 18.6.3)
class Field;
  rand bit [7:0] value;
  int npre, npost;
  constraint c_value {value inside {[0 : 15]};}
  function void pre_randomize;
    ++npre;
  endfunction
  function void post_randomize;
    ++npost;
  endfunction
endclass

class Reg;
  rand Field f;
  int npre, npost;
  function new;
    f = new;
  endfunction
  function void pre_randomize;
    ++npre;
  endfunction
  function void post_randomize;
    ++npost;
  endfunction
endclass

class Block;
  rand Reg r;
  function new;
    r = new;
  endfunction
endclass

module t;
  initial begin
    automatic Reg r0 = new;  // Reg randomized directly as well
    automatic Block b = new;
    automatic int ok;
    ok = r0.randomize();
    `checkd(ok, 1);
    `checkd(r0.npre, 1);
    `checkd(r0.npost, 1);
    `checkd(r0.f.npre, 1);
    `checkd(r0.f.npost, 1);
    ok = b.randomize();
    `checkd(ok, 1);
    `checkd(b.r.npre, 1);
    `checkd(b.r.npost, 1);
    `checkd(b.r.f.npre, 1);
    `checkd(b.r.f.npost, 1);
    `checkd(b.r.f.value < 16, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
