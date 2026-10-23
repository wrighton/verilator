// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

timeunit 1ns; timeprecision 1ps;

class Cls;
  // A class keeps these pragmas, so the tree dump shows them
  timeunit 1ns;
  timeprecision 1ps;
endclass

module t;
  /*verilator inline_module*/
  Cls c;
endmodule
