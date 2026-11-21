// DESCRIPTION: Verilator: a concurrent assertion in an action block of a concurrent assertion
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 16.14.1: "The action_block shall not include any concurrent assert, assume,
// or cover statement." 16.14.2, 16.14.3: the same for an assumption and a cover statement.
module t (
    input clk
);

  bit p = 1, q = 1;

  assert property (@(posedge clk) p) begin
    assert property (@(posedge clk) q);  // Bad: in a pass action
  end
  else begin
    assume property (@(posedge clk) q);  // Bad: in a fail action
  end

  assert property (@(posedge clk) p)
  else begin
    begin
      cover property (@(posedge clk) q);  // Bad: in a block of a fail action
    end
  end

  cover property (@(posedge clk) p) begin
    assert property (@(posedge clk) q);  // Bad: in a cover's statement
  end

  assert property (@(posedge clk) p) begin
    if (1'b0) assert property (@(posedge clk) q);  // Bad: also under a constant-false if
  end

  assert property (@(posedge clk) p ##1 q)
  else begin
    assert property (@(posedge clk) q);  // Bad: in an action of a multi-cycle property
  end

  assert property (@(posedge clk) p |-> ##1 q) begin
    assert property (@(posedge clk) q);  // Bad: in a pass action of a multi-cycle implication
  end

  assume property (@(posedge clk) p) begin
    assert property (@(posedge clk) q);  // Bad: in a pass action of an assumption
  end

  cover sequence (@(posedge clk) p ##1 q) begin
    assert property (@(posedge clk) q);  // Bad: in a cover sequence's statement
  end

endmodule
