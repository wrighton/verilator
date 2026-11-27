// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The solve after a with-block's size solve keeps the with-block's constraints, also when the
// class constraints in force alone could be sampled without the solver, as with the arrays of a
// null member object left out

class Sized;
  rand bit [6:0] q[$];
  constraint c_q {q.size() inside {[1 : 3]};}
endclass

class Outer;
  rand Sized sized;
  rand bit [3:0] len;
  bit [3:0] lo = 4'd3;
  bit [3:0] hi = 4'd6;
  constraint c_len {len < 4'd8;}
  function new();
    sized = new;
  endfunction
endclass

module t;
  initial begin
    automatic Outer o = new;
    automatic int randomize_result;
    // A with-block sizing the member object's array
    randomize_result = o.randomize() with {sized.q.size() == 2;};
    `checkd(randomize_result, 1);
    `checkd(o.sized.q.size(), 2);
    `checkd(o.len < 4'd8, 1'b1);
    o.sized = null;
    repeat (40) begin
      randomize_result = o.randomize() with {len > 4'd2;};
      `checkd(randomize_result, 1);
      `checkd(o.len > 4'd2 && o.len < 4'd8, 1'b1);
      // Bounds read from state, which the solve after the size solve reads again
      randomize_result = o.randomize() with {len inside {[lo : hi]};};
      `checkd(randomize_result, 1);
      `checkd(o.len >= 4'd3 && o.len <= 4'd6, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
