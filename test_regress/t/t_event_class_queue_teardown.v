// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The model is destroyed while processes wait on wait lists of a package event, which a
// different instance than the scheduler owns, so the event is destroyed first: once without
// finishing, and once finishing while a fired wait list and a newer one on the same event are
// both still waited on. Only with threads does the second case reach that, as the $finish of
// a parallel MTask stays pending until the end of the evaluation.
package pkg;
  event ev;
endpackage

module t;
  class Waiter;
    task wait_ev();
      @(pkg::ev);
    endtask
  endclass
  class Firer;
    bit go;
    Waiter late = new;
    task fire_late();
      wait (go);
      // A pending $finish keeps this fired list from being drained, and the later wait from
      // joining it, so both lists remain
      ->pkg::ev;
      fork
        late.wait_ev();
      join_none
    endtask
  endclass

  Waiter early = new;
  Firer firer = new;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  int cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;
  always_ff @(posedge clk) begin
    if (cyc == 5 && $test$plusargs("finish")) begin
      firer.go = 1;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
  initial begin
    fork
      early.wait_ev();
      firer.fire_late();
    join_none
  end
endmodule
