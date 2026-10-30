// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The fail action of a strong property also runs at the end of simulation, in a final block,
// where a timing control could not resume. An action with one runs during simulation, and the
// default error is reported at the end instead. A task the action calls is not checked for one:
// at the end it runs up to its timing control (known limit).

module t;
  logic clk = 1'b0;
  int cyc = 0;
  // Fails the attempts of ticks 0 and 1 on tick 2; those of ticks 3 to 5 are pending at the end
  wire ok = cyc != 2;

  initial forever #5 clk = ~clk;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  assert property (@(posedge clk) s_always [1:3] ok)
  else begin
    #1 $display("[%0t] DELAY", $time);
  end

  assert property (@(posedge clk) s_always [1:3] ok)
  else @(posedge clk) $display("[%0t] EVENT", $time);

  // A timing control in a task the action calls, directly or through another task: the
  // action runs at the end as written, up to that timing control
  task automatic delay_task;
    #1 $display("[%0t] TASK", $time);
  endtask
  task automatic outer_task;
    delay_task();
  endtask
  task automatic wait_task;
    wait (clk) $display("[%0t] WAIT", $time);
  endtask
  task automatic plain_task;
    $display("[%0t] PLAIN", $time);
  endtask

  assert property (@(posedge clk) s_always [1:3] ok)
  else delay_task();

  assert property (@(posedge clk) s_always [1:3] ok)
  else begin
    plain_task();
    outer_task();
  end

  assert property (@(posedge clk) s_always [1:3] ok)
  else wait_task();

  // A task without a timing control runs at the end of simulation as written
  assert property (@(posedge clk) s_always [1:3] ok)
  else plain_task();

  // The end-of-simulation checks of s_until and s_eventually, where a timing control in a task
  // the action calls does not stop the checks after it
  assert property (@(posedge clk) 1'b1 s_until (cyc == 100))
  else begin
    #1 $display("[%0t] UNTIL", $time);
  end
  assert property (@(posedge clk) s_eventually (cyc == 100))
  else begin
    #1 $display("[%0t] EVENTUALLY", $time);
  end
  assert property (@(posedge clk) 1'b1 s_until (cyc == 100))
  else delay_task();
  assert property (@(posedge clk) 1'b1 s_until (cyc == 100))
  else $display("[%0t] UNTIL_PLAIN", $time);

  // A virtual task, of which the override called has a timing control, or none does
  class Base;
    virtual task report;
      $display("[%0t] BASE", $time);
    endtask
  endclass
  class Delayed extends Base;
    virtual task report;
      #1 $display("[%0t] DELAYED", $time);
    endtask
  endclass
  class Other;
    virtual task report;
      $display("[%0t] OTHER", $time);
    endtask
  endclass
  class OtherPlain extends Other;
    virtual task report;
      $display("[%0t] OTHER_PLAIN", $time);
    endtask
  endclass
  Delayed delayed = new;
  Base base = delayed;
  OtherPlain otherPlain = new;
  Other other = otherPlain;

  assert property (@(posedge clk) s_always [1:3] ok)
  else base.report();

  assert property (@(posedge clk) s_always [1:3] ok)
  else other.report();

endmodule
