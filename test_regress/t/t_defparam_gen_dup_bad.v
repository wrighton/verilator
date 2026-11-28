// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Several defparams to one parameter in a generate block, which may not be built, still give a
// duplicate parameter connection

module leaf #(
    parameter int P = 61
);
endmodule

module wrap #(
    parameter int PICK = 0
);
  leaf chosen_if ();
  leaf chosen_case ();
  leaf chosen_for ();
  if (PICK == 1) begin : g_if
    defparam chosen_if.P = 7;
    defparam chosen_if.P = 11;  // Bad
  end
  case (PICK)
    1: begin : g_case
      defparam chosen_case.P = 7;
      defparam chosen_case.P = 11;  // Bad
    end
    default: ;
  endcase
  for (genvar i = 0; i < PICK; ++i) begin : g_for
    defparam chosen_for.P = 7;
    defparam chosen_for.P = 11;  // Bad
  end
endmodule

module t;
  wrap #(.PICK(0)) u_pick0 ();
  wrap #(.PICK(1)) u_pick1 ();
endmodule
