// DESCRIPTION: Verilator: Upward assertion control name missing above one instance
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module mid;
  initial $assertoff(0, gb.inner);
endmodule

module par;
  if (1) begin : gb
    if (1) begin : inner
      initial check : assert (1'b1);
    end
  end
  mid m ();
endmodule

// No gb is above this mid
module qar;
  mid m ();
endmodule

module t;
  qar q ();
  par p ();
endmodule
