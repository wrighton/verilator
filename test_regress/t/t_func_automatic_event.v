// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// An event in a task inlined in a class task: it is not reset where declared,
// so its later assignment of a constant stays where it is

module t;
  task automatic t_event(int sel);
    event ev;
    if (sel != 0) ->ev;
    ev = null;
  endtask

  class Cls;
    task run(int sel);
      t_event(sel);
    endtask
  endclass

  initial begin
    automatic Cls c = new;
    c.run(1);
    c.run(0);
  end
endmodule
