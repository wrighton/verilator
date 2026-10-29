// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// 'local::' in 'randomize() with' on another object of the caller's own class
// binds to the caller object, not the randomized one (IEEE 1800-2023 18.7.1)
class Cls;
  rand int x;
  int lim;
  function int rand_lim(Cls other);
    return other.randomize() with { x == local::lim; };
  endfunction
  function int rand_x(Cls other);
    return other.randomize() with { x == local::x + 1; };
  endfunction
endclass

module t;
  initial begin
    automatic Cls a = new;
    automatic Cls b = new;
    for (int i = 0; i < 3; ++i) begin
      a.lim = i * 10 + 3;
      b.lim = i * 10 + 5;
      `checkd(a.rand_lim(b), 1);
      `checkd(b.x, i * 10 + 3);
      a.x = i * 7;
      `checkd(a.rand_x(b), 1);
      `checkd(b.x, i * 7 + 1);
      `checkd(a.x, i * 7);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
