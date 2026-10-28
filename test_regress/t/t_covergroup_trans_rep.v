// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Test consecutive repetition in transition bins, '3 [* 3]' being '3 => 3 => 3'
// (IEEE 1800-2023 19.5.2)

module t;
  localparam int N = 2;
  logic [1:0] v;

  covergroup cg;
    cp: coverpoint v {
      bins rep = (3 [*3]);
      bins rng = (3 [*2:3]);
      bins param = (3 [*N]);
      bins mid = (0 => 1 [*2] => 2);
      bins multi = (1, 2 [*2] => 0);
      bins arr[] = (2 [*2]), (0 => 1);
      // More than 64 values, matched from a table
      bins long = (1 [*70]);
    }
    cp_ign: coverpoint v {
      bins zo = (0 => 1);
      ignore_bins ign = (0 [*2]);
    }
  endgroup

  cg c = new;

  initial begin
    // 3,3,3,3: 'rep' completes at the third and fourth, 'rng' at the second to fourth
    repeat (4) begin
      v = 3;
      c.sample();
    end
    // 0,1,1,2: 'mid' completes, and 'multi' starts
    v = 0;
    c.sample();
    v = 1;
    c.sample();
    v = 1;
    c.sample();
    v = 2;
    c.sample();
    // 1,2,0: 'multi' completes; 'arr' never saw 2 => 2, but 0 => 1 twice
    v = 0;
    c.sample();
    // 1 seventy times: 'long' completes
    repeat (70) begin
      v = 1;
      c.sample();
    end
    // 0,0: 'ign'
    repeat (2) begin
      v = 0;
      c.sample();
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
