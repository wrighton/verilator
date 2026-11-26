// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  int got[$];

  // Not queued by the calling process, as lowered by V3AssertNfa: the variables of the task are
  // out of its scope
  task automatic loop_var();
    for (int i = 0; i < 3; i++) begin
      assert property (@(posedge clk) 1'b0 ##1 1'b1)
      else got.push_back(i);
    end
  endtask

  // Queued, but a static variable of the task is read after the task returned
  task static_local();
    int n;
    n = 1;
    assert property (@(posedge clk) n == 1);
  endtask

  int seen;
  task automatic action_static();
    assert property (@(posedge clk) 1) begin
      static int kept;
      kept = 17;
      seen = kept;
    end
  endtask

  initial begin
    action_static();
    loop_var();
    static_local();
  end
endmodule
