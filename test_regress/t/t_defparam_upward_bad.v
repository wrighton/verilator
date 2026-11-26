// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A defparam path found upwards that may name a different instance from each instance of its
// module. Generate blocks are not built yet when defparam paths are resolved, so one in a
// generate block is unsupported even if the block is not built.

module leaf #(
    parameter int P = 0
);
endmodule

module bank;
  leaf u ();
endmodule

// Names t.u from d, and a.t.u from a.c
module cfg;
  defparam t.u.P = 8;
endmodule

module box;
  bank t ();
  cfg c ();
endmodule

// Names hv.s only from a generate block, and hu.s from one not built
module cfg_gen;
  defparam s.P = 47;
endmodule

module holder #(
    parameter bit USE = 1
);
  leaf s ();
  if (USE) begin : g
    cfg_gen c ();
  end
endmodule

// Names t.u from dd, and dw.t.u from an instance in a generate block not built
module cfg_dead;
  defparam t.u.P = 47;
endmodule

module box_dead;
  bank t ();
  if (0) begin : inactive
    cfg_dead c ();
  end
endmodule

module t;
  leaf u ();
  box a ();
  cfg d ();
  holder #(.USE(0)) hu ();
  holder #(.USE(1)) hv ();
  box_dead dw ();
  cfg_dead dd ();
endmodule
