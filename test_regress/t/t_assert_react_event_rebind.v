// DESCRIPTION: Verilator: a reactive waiter stays bound to the event it originally waited on
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

class Box;
  event e;
  event original, replacement;
  task saveOriginal();
    original = e;
  endtask
  task fireReplacement();
    e = replacement;
    ->e;
  endtask
  task fireOriginal();
    ->original;
  endtask
  task waitForEvent(ref int observed, ref int data);
    @(e);
    observed = data;
  endtask
endclass

// Keep Verilator's existing event-list behavior in both regions: a surviving alias can still
// fire the original event after the member is rebound. This is not an LRM guarantee.
module t;
  bit clk = 0;
  int cyc = 0, data = 0, observed = -1, activeObserved = -1;
  Box box = new;
  initial begin
    box.saveOriginal();
    box.waitForEvent(activeObserved, data);
  end
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  assert property (@(posedge clk) 1'b1 until 1'b1) begin
    case (cyc)
      1: box.waitForEvent(observed, data);
      2: box.fireReplacement();
      3: begin
        data <= cyc;
        box.fireOriginal();
      end
      default: ;
    endcase
  end

  always @(negedge clk) begin
    if (cyc == 2) begin
      `checkd(observed, -1);
      `checkd(activeObserved, -1);
    end
    if (cyc == 3) begin
      `checkd(observed, 0);
      `checkd(activeObserved, 3);
      `checkd(data, 3);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
