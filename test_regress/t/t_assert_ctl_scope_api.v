// DESCRIPTION: Verilator: Global C++ and runtime controls over selected assertions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module assertion_leaf (
    input bit clk,
    output int failures
);
  initial failures = 0;
  always @(posedge clk) begin
    labelled_check :
    assert (1'b0)
    else failures++;
  end
endmodule

module t (
    input bit clk,
    output int afails,
    output int bfails
);
  assertion_leaf a (
      clk,
      afails
  );
  assertion_leaf b (
      clk,
      bfails
  );
  initial begin
    $assertoff(0, a.labelled_check);
    $assertcontrol(1, 2, 1, 0, a.labelled_check);  // Lock the selected assertion
  end
endmodule
