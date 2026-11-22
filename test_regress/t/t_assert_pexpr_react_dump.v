// DESCRIPTION: Verilator: Tree dumps of reactive region constructs
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input p,
    input q
);
  event ev;
  int n = 0;
  int s = 0;
  task report();
    ++n;
  endtask
  // An observed deferred assertion, with an action waiting for an event in the reactive region
  // set, and a const cast
  always @(posedge clk)
    assert #0 (p)
    else report();
  always @(posedge clk) begin
    s = n;
    assert property (p until q)
    else begin
      @(ev);
      n = const'(s);
    end
  end
endmodule
