// DESCRIPTION: Verilator: statements legal in an action block of a concurrent assertion
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 16.14.1 forbids only concurrent assertions in an action block: immediate and
// deferred immediate assertions, and calls of a task that has a concurrent assertion, are legal.
module t (
    input clk
);

  bit p = 1, q = 1;
  int n = 0;

  task automatic tk();
    assert property (@(posedge clk) q) ++n;
  endtask

  assert property (@(posedge clk) p) begin
    assert (q);
    assert #0 (q);
    assert final (q);
    cover (q) ++n;
    tk();
  end
  else begin
    assume (q);
  end

endmodule
