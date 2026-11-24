// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    output bit is_str
);
  wrap #(.S("ab")) w (.is_str(is_str));
endmodule

module wrap #(
    parameter string S = "x"
) (
    output bit is_str
);
  mid #(.P(S)) u (.is_str(is_str));
endmodule

module mid #(
    parameter P = 0
) (
    output bit is_str
);
  /*verilator hier_block*/
  assign is_str = $typename(P) == "string";
endmodule
