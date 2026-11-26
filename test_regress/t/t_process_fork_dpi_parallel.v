// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A clocked block calls a context DPI import whose C code calls a DPI export that starts two
// processes (IEEE 1800-2023 9.3.2, 35.5.3): one waits on a delay, the other waits on a class
// event that another block fires from the same cycle on. The block calling the import controls
// processes, so it runs alone (checked by the MTask statistics); both started processes complete.
module t;
  timeunit 1ns; timeprecision 1ps;

  localparam int FIRST = 2;  // Cycle of the starts
  localparam int LAST = 20;  // Cycle of the last event
  localparam realtime AFTER = 3ns;  // Delay of the started process

  logic clk = 1'b0;
  always #5ns clk = ~clk;
  int cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;

  class Waiter;
    event e;
    int n;
    task wait_e();
      @e;
      ++n;
    endtask
    function void fire();
      ->e;
    endfunction
  endclass
  Waiter w = new;

  int delayed = 0;
  always_ff @(posedge clk) if (cyc >= FIRST && cyc < LAST) w.fire();

  export "DPI-C" function dpix_start;
  function void dpix_start();
    fork
      #AFTER delayed++;
      w.wait_e();
    join_none
  endfunction
  import "DPI-C" context function void dpii_start();
  always_ff @(posedge clk) if (cyc == FIRST) dpii_start();

  initial begin
    #300ns;
    `checkd(delayed, 1);
    `checkd(w.n, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
