// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // verilator lint_off PINMISSING
  sub_p1_real sub_p1_real ();
  sub_p0_real sub_p0_real ();
  sub_p1_struct sub_p1_struct ();
  // verilator lint_on PINMISSING
endmodule

`unconnected_drive pull1
module sub_p1_real (
    input real i
);
endmodule

`unconnected_drive pull0
module sub_p0_real (
    input real i
);
endmodule

typedef struct {
  logic a;
  real r;
} struct_real_t;

`unconnected_drive pull1
module sub_p1_struct (
    input var struct_real_t i
);
endmodule

`nounconnected_drive
