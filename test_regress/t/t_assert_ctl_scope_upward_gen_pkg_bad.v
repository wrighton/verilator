// DESCRIPTION: Verilator: Upward assertion control name naming a package task in one instance
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  task automatic gb();
    begin : inner
      check : assert (1'b1);
    end
  endtask
endpackage

module mid;
  initial $assertoff(0, gb.inner);
endmodule

// In qar, gb names the package task imported there
module qar;
  import pkg::*;
  mid m ();
endmodule

module par;
  if (1) begin : gb
    if (1) begin : inner
      initial check : assert (1'b1);
    end
  end
  mid m ();
endmodule

module t;
  qar q ();
  par p ();
endmodule
