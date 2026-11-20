// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A constant function that writes a select of an associative array element cannot be
// evaluated by Verilator
module t;
  function automatic int assoc_write();
    int assoc[int];
    assoc[0][3] = 1'b1;
    return assoc[0];
  endfunction
  localparam int P = assoc_write();
  initial $display(P);
endmodule
