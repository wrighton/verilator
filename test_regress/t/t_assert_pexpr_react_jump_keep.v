// DESCRIPTION: Verilator: Jumps out of concurrent assertion actions kept where they stay in the process
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t;
  bit clk = 0;
  int cyc = 0;
  bit p = 0, q = 0;
  int after1 = 0, n2 = 0, act3 = 0, after3 = 0, act4 = 0, x4 = 0;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  // A cover deleted without --coverage-user takes its action along
  always @(posedge clk) begin : blk1
    cover property (p until q) disable blk1;
    ++after1;
  end

  // Also a task's cover, moved beside the task
  task automatic tk();
    begin : tblk
      cover property (@(posedge clk) q) disable tblk;
      ++n2;
    end
  endtask
  always @(posedge clk) tk();

  // A Boolean procedural assertion whose action jumps stays at its statement, in the procedure,
  // and disables the block the procedure executes (IEEE 1800-2023 9.6.2)
  always @(posedge clk) begin : blk3
    assert property (q)
    else begin
      ++act3;
      disable blk3;
    end
    ++after3;
  end

  // A disable of a block of the action itself stays within the action's process
  always @(posedge clk) begin
    assert property (p until q)
    else begin : ablk
      ++act4;
      assert (q)
      else disable ablk;
      ++x4;
    end
  end

  always @(negedge clk) begin
    if (cyc == 4) begin
      `checkd(after1, 4);
      `checkd(n2, 4);
      `checkd(act3, 4);
      `checkd(after3, 0);
      `checkd(act4, 4);
      `checkd(x4, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
