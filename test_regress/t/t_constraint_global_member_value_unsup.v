// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Entry;
  rand bit [7:0] x;
endclass

// Selects elements by two index expressions, which a constraint cloned into a containing class
// does not support
class Member;
  rand Entry arr[4];
  rand bit [7:0] y;
  constraint c_arr {
    foreach (arr[i]) if (i < 2) arr[(i * 2) / 2].x != arr[(i * 2) / 2 + 1].x;
    y < 3;
  }
  function new();
    foreach (arr[i]) arr[i] = new;
  endfunction
endclass

// Its constraint selects the member's value member, so the member's constraints are solved with
// it, cloned, which reports the selects unsupported rather than solving the two apart
class Holder;
  rand Member m;
  rand bit [7:0] k;
  constraint c_k {
    k == m.y;
    k == 9;
  }
  function new();
    m = new;
  endfunction
endclass

module t;
  Holder holder;
  int ok;
  initial begin
    holder = new;
    ok = holder.randomize();
    $finish;
  end
endmodule
