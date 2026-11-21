// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A select beyond an unpacked array of nets is not a net destination, so the local driver of
// the formal is not returned to it, while one within the array is
module beyond_driver (
    output wire p
);
  assign p = 1'b1;
endmodule

module beyond_sink (
    input wire p
);
endmodule
bind beyond_sink beyond_driver d (.p(p));

module t;
  wire beyond_nets[1:0];
  wire within_nets[1:0];
  logic value = 1'b0;
  // A value connection of the formal resolves its local driver with the connection
  beyond_sink u_value (.p(value));
  // verilator lint_off SELRANGE
  beyond_sink u_beyond (.p(beyond_nets[2]));
  // verilator lint_on SELRANGE
  beyond_sink u_within (.p(within_nets[1]));
endmodule
