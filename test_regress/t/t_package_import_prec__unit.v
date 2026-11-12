// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilator lint_off IMPORTSTAR
import p2::*;
// verilator lint_on IMPORTSTAR
import p2::y;

module sub;
  int a = x;
  int b = y;
  int c = z;
endmodule

// A later declaration in $unit hides its wildcard imported name, also after a reference
int z = 5;
