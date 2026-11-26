// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

class Pair;
  rand bit [7:0] v;
endclass

// The member of the last element of a queue is read as state, and as out of range of an empty
// queue, as an element by an index is
class Tail;
  rand Pair q[$];
  constraint c_q {q[$].v == 8'd77;}
endclass

class TailHolder;
  rand Tail t;
  rand bit [7:0] k;
  constraint c_k {k == 1;}
  function new();
    t = new;
  endfunction
endclass

module t;
  TailHolder holder;
  Pair first;
  Pair last;
  int ok;
  initial begin
    holder = new;
    ok = holder.randomize();
    `checkh(ok, 0);
    first = new;
    last = new;
    last.v = 8'd77;
    last.v.rand_mode(0);
    holder.t.q.push_back(first);
    holder.t.q.push_back(last);
    ok = holder.randomize();
    `checkh(ok, 1);
    `checkh(holder.k, 8'd1);
    `checkh(last.v, 8'd77);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
