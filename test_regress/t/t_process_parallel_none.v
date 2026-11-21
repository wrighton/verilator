// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Clocked blocks, which may be in different parallel MTasks, start processes and delay
// assignments themselves, and call module tasks, class functions and a context DPI import whose
// DPI export does not control processes, but none of them controls processes, so all of them
// still run in parallel
module t;
  timeunit 1ns; timeprecision 1ps;

  localparam int CYCLES = 4;
  localparam realtime AFTER = 3ns;

  logic clk = 1'b0;
  always #5ns clk = ~clk;
  int cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;

  // Processes started by the blocks themselves
  int forked_a = 0;
  int forked_b = 0;
  always @(posedge clk) begin
    if (cyc < CYCLES)
      fork
        #AFTER forked_a++;
      join_none
  end
  always @(posedge clk) begin
    if (cyc < CYCLES)
      fork
        #AFTER forked_b++;
      join_none
  end

  // Processes started through module tasks
  int task_a = 0;
  int task_b = 0;
  task automatic start_a();
    fork
      #AFTER task_a++;
    join_none
  endtask
  task automatic start_b();
    fork
      #AFTER task_b++;
    join_none
  endtask
  always @(posedge clk) if (cyc < CYCLES) start_a();
  always @(posedge clk) if (cyc < CYCLES) start_b();

  // Delayed assignments
  int delayed_a = 0;
  int delayed_b = 0;
  always_ff @(posedge clk) delayed_a <= #AFTER cyc;
  always_ff @(posedge clk) delayed_b <= #AFTER cyc;

  // Calls of class functions
  class Acc;
    int sum = 0;
    function void add(int value);
      sum += value;
    endfunction
  endclass
  Acc acc_a = new;
  Acc acc_b = new;
  always_ff @(posedge clk) if (cyc < CYCLES) acc_a.add(cyc);
  always_ff @(posedge clk) if (cyc < CYCLES) acc_b.add(cyc);

  // A context DPI import whose DPI export only computes
  export "DPI-C" function dpix_twice;
  function int dpix_twice(int value);
    return 2 * value;
  endfunction
  import "DPI-C" context function int dpii_twice(int value);
  int twice = 0;
  always_ff @(posedge clk) if (cyc < CYCLES) twice <= dpii_twice(cyc);

  initial begin
    #100ns;
    `checkd(forked_a, CYCLES);
    `checkd(forked_b, CYCLES);
    `checkd(task_a, CYCLES);
    `checkd(task_b, CYCLES);
    `checkd(delayed_a, cyc - 1);
    `checkd(delayed_b, cyc - 1);
    `checkd(acc_a.sum, CYCLES * (CYCLES - 1) / 2);
    `checkd(acc_b.sum, CYCLES * (CYCLES - 1) / 2);
    `checkd(twice, 2 * (CYCLES - 1));
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
