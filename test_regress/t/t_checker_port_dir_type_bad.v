// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A checker port with an explicit direction needs a data type (IEEE 1800-2023 17.2)
checker chk_output (int a, output b);
endchecker

checker chk_input (input c);
endchecker

// Without a direction, the type of the previous port, or input untyped for the first
checker chk_ok (d, int e, f, output int g, h, input [3:0] i, input signed j);
endchecker

module t;
endmodule
