// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Defparams in generate blocks, which may not be built, to one parameter of an instance in
// another module still give a duplicate parameter connection

module leaf #(
    parameter int P = 61
);
endmodule

module wrap #(
    parameter int PICK = 0
);
  if (PICK == 1) begin : g_one
    defparam t.u_leaf.P = 7;
  end
  else begin : g_zero
    // Bad
    defparam t.u_leaf.P = 11;
  end
endmodule

module t;
  leaf u_leaf ();
  wrap #(.PICK(1)) u_pick1 ();
endmodule
