// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under The Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// units < precision
`timescale 1ps/1ns

// Bad scale
`timescale frump
`timescale 1xs
`timescale 2ps
`timescale 1ns / frump
`timescale 1ns / 1ps /extra

module t;
  timeunit 2ps;  // Bad
  timeprecision 2ps;   // Bad
endmodule

module t_late (
    input a
);
  logic b;
  timeunit 1ns;  // Bad, after other items
  timeprecision 1ps;  // Bad, after other items
endmodule

interface ifc_late;
  logic b;
  timeunit 1ns;  // Bad, after other items
endinterface

program prog_late;
  logic b;
  timeunit 1ns;  // Bad, after other items
endprogram

package pkg_late;
  logic b;
  timeunit 1ns;  // Bad, after other items
endpackage

module t_mismatch;
  timeunit 1ns / 1ps;
  logic b;
  timeunit 1ns;  // OK, matches
  timeprecision 1ps;  // OK, matches
  timeunit 1ps;  // Bad, mismatch
  timeprecision 1fs;  // Bad, mismatch
endmodule

module t_prec_first;
  /*verilator public_module*/
  timeprecision 1ps;
  timeunit 1ns;
endmodule

module t_prec_coarse;
  timeunit 1ns;
  timeprecision 10ns;  // Bad, coarser than unit
endmodule

module t_prec_coarse_slash;
  timeunit 1ns / 10ns;  // Bad, coarser than unit
endmodule
