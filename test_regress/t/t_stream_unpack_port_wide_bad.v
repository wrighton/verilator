// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A stream wider than the unpacked array input port it is connected to is an
// error (IEEE 1800-2023 11.4.14).

module sub (
    input byte ia[2]
);
endmodule

module t;
  bit [23:0] p24;
  sub u (.ia({>>{p24}}));
endmodule
