// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Transition bins with repetitions not supported are ignored, with a COVERIGN

module t;
  localparam int ZERO = 0;
  localparam int UNB = $;
  logic [1:0] v;

  covergroup cg(int n);
    cp: coverpoint v {
      bins ok = (1 => 2);
      bins goto1 = (3 [->2]);
      bins goto2 = (0 => 3 [->1:2]);
      bins noncons1 = (3 [=2] => 1);
      bins noncons2 = (3 [=1:2]);
      bins zero = (3 [*ZERO]);
      bins reversed = (3 [*3:2]);
      bins unbounded = (3 [*1:UNB]);
      bins unbounded2 = (3 [*1:$]);
      bins x = (3 [*'x]);
      bins real_count = (3 [*2.0]);
      bins tolerance = ([2 +/- 1] [*2]);
      bins nonconst = (3 [*n]);
      bins huge = (3 [*70000]);
      ignore_bins ign = (1 => 0 [->2]);
    }
    // Only ignored bins remain, and no automatic bins are created
    cp_dropped: coverpoint v {bins goto3 = (0 [->2] => 1);}
  endgroup

  cg c = new(2);
endmodule
