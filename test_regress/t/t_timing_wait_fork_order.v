// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Processes in 'wait fork' and processes waiting on a condition resume in the order they started
// waiting, when their children complete in the time step the condition is set
class C;
  bit flag;
endclass

class W;
  task automatic run(C c, string name, ref string order);
    wait (c.flag);
    order = {order, name};
  endtask
endclass

module t;
  C c = new;
  W w = new;
  string order = "";

  initial begin : A
    fork
      #5;
    join_none
    wait fork;
    order = {order, "A"};
  end
  initial begin : E
    #1;
    w.run(c, "E", order);
  end
  initial begin : F
    fork
      #5;
    join_none
    #2;
    wait fork;
    order = {order, "F"};
  end
  initial begin : G
    #3;
    w.run(c, "G", order);
  end
  initial #5 c.flag = 1;

  initial begin
    #6;
    `checks(order, "AEFG");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
