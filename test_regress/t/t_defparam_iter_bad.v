// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  for (genvar i = 0; i < 2; ++i) begin : blk
    sub u ();
  end
  if (1) begin : gblk
    sub u ();
  end
  defparam gblk[0].u.P = 1;  // Bad: not a generate loop
  defparam t[0].blk[0].u.P = 1;  // Bad: not a generate loop, the top module
endmodule

module sub;
  parameter P = 0;
endmodule
