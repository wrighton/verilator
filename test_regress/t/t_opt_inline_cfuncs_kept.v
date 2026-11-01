// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Register-model style classes: the nested pre/post_randomize callbacks of
// Reg are also called from Block, so are kept, and are not inlined into
// Reg's randomize()

class Field;
  rand int value;
  int npre;
  int npost;
  function void pre_randomize;
    npre++;
  endfunction
  function void post_randomize;
    npost++;
  endfunction
endclass

class RegBase;
endclass

class Reg extends RegBase;
  rand Field f0, f1, f2, f3, f4, f5;
  function new;
    f0 = new;
    f1 = new;
    f2 = new;
    f3 = new;
    f4 = new;
    f5 = new;
  endfunction
  function int sum;
    return f0.value + f1.value + f2.value + f3.value + f4.value + f5.value;
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
    automatic Reg r = new;
    automatic RegBase rb = r;
    automatic Block b = new;
    automatic int sums = 0;
    automatic int ok;
    // Directly and through a base handle
    for (int i = 0; i < 10; ++i) begin
      ok = r.randomize();
      `checkd(ok, 1);
      sums += r.sum();
      ok = rb.randomize();
      `checkd(ok, 1);
      sums += r.sum();
    end
    if (sums == 0) `stop;
    `checkd(r.f0.npre, 20);
    `checkd(r.f5.npost, 20);
    ok = b.randomize();
    `checkd(ok, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
