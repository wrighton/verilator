// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The type of a checker output port shall not be untyped, sequence or property
// (IEEE 1800-2023 17.2)
checker chk_untyped (input logic a, output untyped b);
endchecker

checker chk_sequence (input logic a, output sequence s);
endchecker

checker chk_property (input logic a, output property p);
endchecker

// The direction of the previous port
checker chk_inherited (output bit a, untyped b);
endchecker

// Inputs may be untyped
checker chk_ok (untyped c, input untyped d, output bit e);
endchecker

module t;
endmodule
