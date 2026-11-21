// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilator lint_off MULTITOP

module inout_default (inout wire x = 1'b0);
endmodule

module ref_default (ref int x = 1);
endmodule

// Ports without a direction below default to inout
module wire_default (wire x = 1'b0);
endmodule

module signed_default (signed x = 1'b0);
endmodule

module range_default ([1:0] x = 2'b0);
endmodule
