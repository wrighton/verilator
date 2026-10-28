// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Covergroup argument values in bins that do not support them yet (IEEE 1800-2023 19.5)

module t;
  covergroup cg(int val) with function sample (int v, real r);
    cp_array: coverpoint v {
      bins arr[] = {val, val + 1};
    }
    cp_wild: coverpoint v {
      wildcard bins wild = {val};
    }
    cp_real: coverpoint r {
      bins real_val = {val};
      bins real_const = {1.0};
    }
    cp_trans: coverpoint v {
      bins trans = (val => val + 1);
    }
  endgroup

  cg c = new(3);

  initial $finish;
endmodule
