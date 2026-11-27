// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A constraint reading the size of an array of a member object through a null handle is an
// evaluation error, which fails randomize() (IEEE 1800-2023 18.5.12), unless a guard keeps the
// read out

class Sized;
  rand bit [6:0] q[$];
  constraint c_q {q.size() inside {[1 : 3]};}
endclass

class Inline;
  rand Sized sized;
  rand bit [3:0] len;
  constraint c_len {len < 4'd8;}
endclass

class Declared;
  rand Sized sized;
  constraint c_size {sized.q.size() == 2;}
endclass

class Guarded;
  rand Sized sized;
  rand bit [3:0] len;
  constraint c_size {if (sized != null) sized.q.size() == 2;}
endclass

module t;
  initial begin
    automatic Inline in = new;
    automatic Declared d = new;
    automatic Guarded g = new;
    automatic int randomize_result;
    repeat (2) begin
      randomize_result = in.randomize() with {sized.q.size() == 2;};
      `checkd(randomize_result, 0);
      randomize_result = in.randomize() with {if (sized != null) sized.q.size() == 2;};
      `checkd(randomize_result, 1);
      randomize_result = in.randomize() with {sized != null -> sized.q.size() == 2;};
      `checkd(randomize_result, 1);
      randomize_result = d.randomize();
      `checkd(randomize_result, 0);
      randomize_result = g.randomize();
      `checkd(randomize_result, 1);
    end
    in.sized = new;
    randomize_result = in.randomize() with {sized.q.size() == 2;};
    `checkd(randomize_result, 1);
    `checkd(in.sized.q.size(), 2);
    d.sized = new;
    randomize_result = d.randomize();
    `checkd(randomize_result, 1);
    `checkd(d.sized.q.size(), 2);
    g.sized = new;
    randomize_result = g.randomize();
    `checkd(randomize_result, 1);
    `checkd(g.sized.q.size(), 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
