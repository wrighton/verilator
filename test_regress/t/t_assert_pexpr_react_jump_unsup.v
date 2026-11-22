// DESCRIPTION: Verilator: Control transfer out of concurrent assertion actions in processes of their own
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  bit clk = 0;
  bit p = 0, q = 0;
  int n = 0;

  // A property expression's attempt and actions run in a forked process
  always @(posedge clk) begin : blk
    assert property (p until q)
    else begin
      ++n;
      disable blk;
    end
    ++n;
  end

  always @(posedge clk) begin
    for (int i = 0; i < 2; i++) begin
      assert property (p until q)
      else break;
    end
  end

  // The loop exit after the $finish is dropped, the break is reported
  always @(posedge clk) begin
    for (int i = 0; i < 2; i++) begin
      assert property (p until q)
      else begin
        $finish;
        break;
      end
    end
  end

  // A task's concurrent assertion gets an always of its own, beside the task
  task automatic tk();
    begin : tblk
      assert property (@(posedge clk) q)
      else disable tblk;
      ++n;
    end
  endtask

  task automatic tr();
    assert property (@(posedge clk) q)
    else return;
    ++n;
  endtask

  always @(posedge clk) begin
    tk();
    tr();
  end
endmodule
