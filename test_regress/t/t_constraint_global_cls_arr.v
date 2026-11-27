// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Foo;
  rand int abcd;
endclass

class Bar;
  rand Foo foo_arr[];

  function new();
    foo_arr = new[12];
    foreach (foo_arr[i]) foo_arr[i] = new;
  endfunction

  constraint c {
    foo_arr.size() == 10;
    foreach (foo_arr[i]) foo_arr[i].abcd < 8;
  }
endclass

// More than 16 objects, so an element's index takes more than one hex digit
class Big;
  rand Foo foo_arr[17];

  function new();
    foreach (foo_arr[i]) foo_arr[i] = new;
  endfunction

  constraint c {
    foreach (foo_arr[i]) foo_arr[i].abcd < 8;
    foo_arr[1].abcd == 3;
    foo_arr[16].abcd == 5;
  }
endclass

module t;
  Bar bar;
  Big big;
  initial begin
    bar = new();
    bar.randomize();
    if (bar.foo_arr.size() != 10) $stop;
    foreach (bar.foo_arr[i]) begin
      if (bar.foo_arr[i].abcd >= 8) $stop;
    end
    big = new();
    if (big.randomize() != 1) $stop;
    foreach (big.foo_arr[i]) begin
      if (big.foo_arr[i].abcd >= 8) $stop;
    end
    if (big.foo_arr[1].abcd != 3) $stop;
    if (big.foo_arr[16].abcd != 5) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
