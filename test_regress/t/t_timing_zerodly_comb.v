// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Zero delays that change no input of combinational logic do not evaluate it again, also
// with a queue written by a process, after a write before the zero delays, and after writes
// read only by clocked logic, by a function called from processes, or by the function itself

class Ctr;
  int n = 0;
  function int get();
    return n;
  endfunction
  function automatic int calc(input int a);
    int r = a;
    for (int j = 0; j < 4; ++j) r = r * 3 + j;
    return r;
  endfunction
endclass

module t;
  int x = 0;
  int y;
  always_comb begin
    y = x + 1;
    if ($time < 2) $display("[%0t] y=%0d", $time, y);  // During the zero delays
  end
  logic clk = 0;
  int q[$];
  int qn;
  always @(posedge clk) qn <= q.size();
  initial begin
    #1 q.push_back(1);
  end
  int z = 0;
  int zr;
  always @(posedge clk) zr <= z;
  Ctr ctr = new;
  int calc_r = 1;
  initial begin
    #1 x = 5;
    repeat (20) #0;
    #0 x = 7;
    repeat (20) begin
      #0 z++;
      ctr.n++;
      calc_r = ctr.calc(calc_r);
    end
    #1 clk = 1;
    #1 `checkd(qn, 1);
    `checkd(zr, 20);
    `checkd(ctr.get(), 20);
    `checkd(calc_r != 1, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
