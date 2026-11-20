// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A partly outside select connected to an input port is a value, not a net destination, so a
// local driver of the formal is a second driver of the formal, not a driver of the source
module part_driver (
    output wire [2:0] p,
    input wire [2:0] value
);
  assign p = value;
endmodule

module part_sink (
    input wire [2:0] p,
    input wire [2:0] value,
    output wire [2:0] seen
);
  assign seen = p;
endmodule
bind part_sink part_driver d (
    .p(p),
    .value(value)
);

module t (
    input wire [2:0] value,
    output wire [2:0] seen
);
  wire [3:0] source;
  // verilator lint_off SELRANGE
  part_sink u (
      .p(source[2+:3]),
      .value(value),
      .seen(seen)
  );
  // verilator lint_on SELRANGE
endmodule
