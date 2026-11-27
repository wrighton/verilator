// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  int q[$];
  int r[$];
  int k;
  bit [63:0] s;
  initial begin
    q = '{1, 2, 3};
    k = 1;
    // '$' as what is subtracted is not a position from the back
    r = q[k-$:2];
    r = q[k-$+:2];
    // A with[] part-select is not supported at a position from the back
    s = {>>{q with [$-1+:2]}};
  end
endmodule
