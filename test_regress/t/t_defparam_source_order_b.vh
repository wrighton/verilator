// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module other_inc;
  defparam t.u_g.s.W = 73;
endmodule

`include "t_defparam_source_order_c.vh"
