// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
endmodule

interface ifc;
endinterface

checker chk;
  sub u_sub ();  // Bad
  ifc u_ifc ();  // Bad
endchecker

module t;
  chk u_chk ();
endmodule
