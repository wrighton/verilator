// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Found only in the library, with its own instances, package import and bind
module lib_checker;
  import lib_pkg::*;
  localparam int CHECK = VALUE;
  lib_sub u_sub ();
  bind lib_checker.u_sub lib_probe #(.ID(5)) u_probe ();
endmodule
