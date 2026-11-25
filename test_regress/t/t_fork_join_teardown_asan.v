// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Processes still waiting at a join when the simulation finishes must not leak

class Payload;
  int data[256];
endclass

class Waiter;
  event ev;
  int hits;
  task run();
    forever begin
      fork
        @ev;
        #3;
      join
      ++hits;
    end
  endtask
endclass

module t;
  event never;

  // Test: join whose branches wait on an event and a delay, holding an object
  int join_done = 0;
  initial begin
    automatic Payload p = new;
    p.data[1] = 1;
    fork
      @never;
      #3;
    join
    join_done = p.data[1];
  end

  // Test: join_any whose branches have not finished yet
  int join_any_done = 0;
  initial begin
    fork
      #100;
      #300;
    join_any
    join_any_done = 1;
  end

  // Test: join in a class method, nested in a join_none
  Waiter w;
  initial begin
    w = new;
    fork
      w.run();
    join_none
    #5;
    ->w.ev;
  end

  // Test: killing a branch waiting forever completes the join
  process forever_p;
  int forever_join_done = 0;
  initial begin
    fork
      begin
        forever_p = process::self();
        wait (0);
      end
    join
    forever_join_done = 1;
  end

  // Test: a join waiting forever keeps its process waiting
  process forever_q;
  int wait_fork_done = 0;
  initial begin
    fork
      begin
        forever_q = process::self();
        fork
          wait (0);
        join
      end
    join_none
    wait fork;
    wait_fork_done = 1;
  end

  initial begin
    #10;
    `checkd(join_done, 0);
    `checkd(join_any_done, 0);
    `checkd(w.hits, 1);
    `checkd(forever_join_done, 0);
    forever_p.kill();
    #1;
    `checkd(forever_join_done, 1);
    `checkd(forever_q.status(), process::WAITING);
    `checkd(wait_fork_done, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
