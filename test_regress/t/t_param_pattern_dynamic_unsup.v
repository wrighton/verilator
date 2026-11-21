// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

class Cls;
endclass

module t;
  localparam Cls P[int] = '{1: null};
  localparam Cls MISSING = P[2];

  typedef int dyn_t[];
  localparam dyn_t SPARSE = '{1: 5, default: 0};
  localparam dyn_t DENSE = '{0: 5};
  localparam int A[dyn_t] = '{SPARSE: 1, DENSE: 2};
  localparam int ADENSE = A[DENSE];
endmodule
