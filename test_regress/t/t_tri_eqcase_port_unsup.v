// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input i,
    output o,
    output p
);
  sub sub (
      .i(i),
      .o(o),
      .p(p)
  );
endmodule

module sub (
    input i,
    output o,
    output p
);
  assign o = i;
  assign p = o === 1'bz;
endmodule
