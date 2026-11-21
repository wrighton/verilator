// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

class Cls;
  int x = 100;
  task get_x(output int arg);
    arg = x;
  endtask
endclass

task automatic test;
  int o;
  Cls c = new;
  fork
    c.get_x(o);
  join_any
  if (o != 100) $stop;
endtask

class Accessor;
  localparam realtime STEP = 1ns;

  task read_value(input int value, output int result);
    #STEP;
    result = value;
  endtask

  task access (inout int data);
    process child;
    bit done = 0;
    fork
      begin
        child = process::self();
        read_value(data + 7, data);
        done = 1;
      end
    join_none
    for (int cycles = 0; cycles < 10 && !done; ++cycles) begin
      #STEP;
    end
    if (!done && child != null) child.kill();
    `checkd(done, 1);
  endtask
endclass

module t;
  initial begin
    Accessor accessor;
    int data;
    accessor = new;
    data = -1;
    for (int calls = 1; calls <= 4; ++calls) begin
      accessor.access(data);
      `checkd(data, -1 + 7 * calls);
    end
    test();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
