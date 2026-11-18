// DESCRIPTION: Verilator: Upward assertion control name imported into an instance above
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  task automatic pk();
    check : assert (1'b1);
  endtask
endpackage

module mid;
  initial $assertoff(0, pk);
endmodule

// From the mid in par, pk is par's generate block. From the mid in qar no pk is visible: the
// task imported into qar is not visible by hierarchical reference into qar (IEEE 1800-2023 26.3)
module qar;
  import pkg::*;
  mid m ();
endmodule

module par;
  if (1) begin : pk
    initial check : assert (1'b1);
  end
  mid m ();
endmodule

module t;
  qar q ();
  par p ();
endmodule
