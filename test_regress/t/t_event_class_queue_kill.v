// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Waits abandoned by a timeout, or by a kill, must not accumulate on event wait lists
class Waiter;
  event e;
  int n;
  int payload[1000];
  task wait_e();
    @e;
    ++n;
  endtask
endclass

module t;
  localparam int ITERATIONS = 50000;
  localparam int CROWD = 20000;  // Waiters staying on one event
  localparam int CROWD_KILLS = 200000;  // Waiters killed one at a time among them
  initial begin
    Waiter w;
    w = new;
    for (int i = 0; i < ITERATIONS; ++i) begin
      fork
        w.wait_e();
        #1;
      join_any
      disable fork;
    end
    `checkd(w.n, 0);
    ->w.e;
    #1;
    `checkd(w.n, 0);
    // A new waiting object each time, whose event never fires again
    for (int i = 0; i < ITERATIONS; ++i) begin
      Waiter tw;
      tw = new;
      fork
        tw.wait_e();
        #1;
      join_any
      disable fork;
    end
    // A process killing itself runs on until it waits
    for (int i = 0; i < ITERATIONS; ++i) begin
      fork
        begin
          Waiter kw;
          kw = new;
          process::self().kill();
          kw.wait_e();
        end
      join_none
      #1;
    end
    // Waiters killed one per time step among many staying on the same event, so dropping each
    // must not scan the others. Sized so that scanning the crowd at each kill, or evaluating the
    // trigger of each of its waiters at each time step, exceeds the CPU limit of the test.
    begin
      Waiter cw;
      process kp;
      cw = new;
      repeat (CROWD) begin
        fork
          cw.wait_e();
        join_none
      end
      for (int i = 0; i < CROWD_KILLS; ++i) begin
        fork
          begin
            kp = process::self();
            cw.wait_e();
          end
        join_none
        #1;
        kp.kill();
      end
      #1;
      `checkd(cw.n, 0);
      ->cw.e;
      #1;
      `checkd(cw.n, CROWD);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // A fired wait list losing its only waiter to a kill still wakes another fired list
  initial begin
    Waiter a;
    Waiter b;
    process p;
    a = new;
    b = new;
    fork
      begin
        p = process::self();
        a.wait_e();
      end
      b.wait_e();
    join_none
    #1;
    ->b.e; ->a.e;
    p.kill();
    #1;
    `checkd(a.n, 0);
    `checkd(b.n, 1);
  end
endmodule
