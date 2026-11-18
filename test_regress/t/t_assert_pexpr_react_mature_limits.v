// DESCRIPTION: Verilator: Procedural concurrent assertions outside the maturation of instances
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Recorded limits of the maturation of procedural instances (IEEE 1800-2023 16.14.6); this pins
// their current results, which are not claimed to follow the standard: an assertion in a task,
// which runs in its own process beside the task, one in a separate fork branch, also of a
// blocking fork, where the resumption from the event control flushes its instance
// (16.14.6.2), a procedural cover, and one in an action of a procedural assertion, which runs
// in a process of its own, followed there by a Kill. Each is followed by a flush point of its
// process, or a Kill, in the time step, which a matured instance would not survive.
module t;
  bit clk = 0;
  int cyc = 0;
  bit p = 1;
  bit q = 1;
  int ntask = 0, nfork = 0, njoin = 0, ncov = 0, nnest = 0;
  event e2;
  task automatic tk();
    assert property (@(posedge clk) p until q) ++ntask;
  endtask
  always @(posedge clk) tk();
  always @(posedge clk) begin
    fork
      begin
        assert property (p until q) ++nfork;
        @(e2);
      end
    join_none
  end
  always @(posedge clk) #0 ->e2;
  always @(posedge clk) begin
    fork
      begin
        assert property (p until q) ++njoin;
        @(e2);
      end
    join
  end
  always @(posedge clk) begin
    cover property (p until q) ++ncov;
    @(e2);
  end
  always @(posedge clk) begin
    assert property (p until q) begin
      assert property (q) ++nnest;
      if (cyc == 2) $assertkill;
    end
  end
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    if (cyc == 4) begin
      $display("ntask=%0d nfork=%0d njoin=%0d ncov=%0d nnest=%0d", ntask, nfork, njoin, ncov,
               nnest);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
