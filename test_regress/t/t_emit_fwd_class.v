// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Common;
  int y = 10;
endclass

class Base;
  Common c;
  function new();
    c = new;
  endfunction
endclass

class ClsA extends Base;
  function int get(Common a);
    return a.y + 1;
  endfunction
endclass

class ClsB extends Base;
  ClsA a;
  function new();
    super.new();
    a = new;
  endfunction
  function int get(Common q);
    return a.get(q) + q.y;
  endfunction
endclass

module sub (
    input int i,
    output int o
);
  // verilator no_inline_module
  ClsA a;
  always @(i) begin
    if (a == null) a = new;
    o = a.get(a.c) + i;
  end
endmodule

module t;
  int i;
  int o1;
  int o2;
  ClsB b;
  sub u1 (
      .i(i),
      .o(o1)
  );
  sub u2 (
      .i(o1),
      .o(o2)
  );
  initial begin
    b = new;
    i = $c32("2");
    #1;
    if (o2 != 24) $stop;
    if (b.get(b.c) != i + 19) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
