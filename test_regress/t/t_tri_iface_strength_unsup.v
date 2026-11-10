// DESCRIPTION: Verilator: Unresolved asymmetric interface strength
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface asymmetric;
  bit data;
  wire value;
  assign (weak0, strong1) value = data;
endinterface

module t;
  asymmetric active ();
  // A non-uniform asymmetric drive needs two value-dependent ranks once another
  // contribution meets it. This is not implemented by the symmetric resolver.
  assign active.value = 1'b1;
endmodule
