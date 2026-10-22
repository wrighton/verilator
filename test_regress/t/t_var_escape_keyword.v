// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 5.6.2: A keyword preceded by an escape character is not a keyword

class Base;
  int \super = 1;
  localparam int D = 1;
  int arr[2];
  event ev;
endclass

class Cls extends Base;
  int \this = 2;
  function int get_this();
    return this.\this + \this ;
  endfunction
  function int get_super();
    return super.\super + \super ;
  endfunction
  // The 'this' and 'super' keywords in other contexts
  task delays();
    #this.D;
    #super.D;
    #this.super.D;
  endtask
  task waits();
    @this.ev;
    @super.ev;
    @this.super.ev;
  endtask
  function int sum_arr();
    int sum = 0;
    foreach (super.arr[i]) sum += super.arr[i];
    foreach (this.super.arr[i]) sum += this.super.arr[i];
    return sum;
  endfunction
endclass

`begin_keywords "1364-2001"
module sub;
  // 'this' is not a keyword in IEEE 1364-2001
  reg this;
  initial begin
    this = 1'b1;
    if (this !== 1'b1) $stop;
  end
endmodule
`end_keywords

module t;
  int \this = 3;
  int \super = 4;

  sub u_sub ();

  initial begin
    Cls c;
    int sum;
    c = new;
    sum = \this + \super ;
    `checkd(sum, 7);
    `checkd(c.get_this(), 4);
    `checkd(c.get_super(), 2);
    c.arr = '{3, 4};
    `checkd(c.sum_arr(), 14);
    fork
      c.waits();
      repeat (3) #1 ->c.ev;
    join
    c.delays();
    `checkd($time, 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
