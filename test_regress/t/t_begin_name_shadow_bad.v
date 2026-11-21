// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  int x;
  initial begin : blk
    begin : blk
      x = blk;  // <--- Error: only blocks named 'blk'
    end
  end
endmodule
