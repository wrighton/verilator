// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

primitive not_u(out, in);
  output out;
  input in;
  table
    0 : 1;
    1 : 0;
  endtable
endprimitive

module t (out, in);
  input in;
  output wire out;
  real v = 0.34;
  not_u #(1.145, v) dut_u (out, in);

  wire out_mtm1, out_mtm2;
  // verilator lint_off MINTYPMAXDLY
  not_u #(1:2:3) dut_mtm1 (out_mtm1, in);
  not_u #(1:2:3, 4:5:6) dut_mtm2 (out_mtm2, in);
  // verilator lint_on MINTYPMAXDLY
endmodule
