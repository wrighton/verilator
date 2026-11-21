// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Crowds of processes wait on mailboxes: one while other logic runs for many time steps, and is
// then served in one time step; another that is served one message per time step
module t;
  timeunit 1ns; timeprecision 1ps;

  // Sized so that testing the condition of each waiter at each time step, or scanning the
  // waiters at each message, exceeds the CPU limit of the test. The crowd served in one time
  // step outnumbers the iterations of the active region that '--converge-limit' allows.
  localparam int CROWD = 20000;
  localparam int STEPS = 200000;
  localparam int SERVED = 100000;

  mailbox #(int) crowd = new;
  mailbox #(int) served = new;
  int ncrowd = 0;
  longint sum = 0;
  int nserved = 0;
  initial begin
    for (int i = 0; i < CROWD; ++i) begin
      fork
        begin
          int v;
          crowd.get(v);
          ++ncrowd;
          sum += longint'(v);
        end
      join_none
    end
    for (int i = 0; i < SERVED; ++i) begin
      fork
        begin
          int v;
          served.get(v);
          ++nserved;
        end
      join_none
    end
  end

  logic clk = 1'b0;
  int cyc = 0;
  always @(posedge clk) cyc++;
  initial begin
    repeat (2 * STEPS) #1 clk = ~clk;
    `checkd(ncrowd, 0);
    for (int i = 0; i < CROWD; ++i) crowd.put(i);
    #1;
    `checkd(ncrowd, CROWD);
    `checkd(sum, longint'(CROWD) * longint'(CROWD - 1) / 2);
    `checkd(cyc, STEPS);
    for (int i = 0; i < SERVED; ++i) begin
      served.put(i);
      #1;
      `checkd(nserved, i + 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
