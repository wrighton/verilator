// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A defparam path found upwards that may name a different instance from each instance of its
// module. Generate blocks are not built yet when defparam paths are resolved, so one in a
// generate block is unsupported even if the block is not built, unless a literal condition, or
// a localparam of a literal value, decides it.

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

// Names t.u from dd, and dw.t.u from an instance in a generate block not built, which is not
// known before parameters are
module cfg_dead;
  defparam t.u.P = 47;
endmodule

module box_dead #(
    parameter bit ON = 0
);
  bank t ();
  if (ON) begin : inactive
    cfg_dead c ();
  end
endmodule

// Names hxu.s and hxv.s from a generate block an X condition does not build, which is not
// taken as known
module cfg_x;
  defparam s.P = 50;
endmodule

module holder_x;
  leaf s ();
  if (1'bx) begin : g
    cfg_x c ();
  end
endmodule

// Names hxe.s from a generate else block of an X condition, which is not taken as known
module cfg_xe;
  defparam s.P = 51;
endmodule

module holder_xe;
  leaf s ();
  if (1'bx) begin : g
  end else begin : e
    cfg_xe c ();
  end
endmodule

// From generate blocks of localparams that do not hold their literal unchanged, which are not
// taken as known
module cfg_tr;
  defparam s.P = 52;
endmodule

module holder_tr;
  localparam bit ON = 2;
  localparam logic [1:0] ON2 = 4;
  localparam bit ON3 = 'h2;
  leaf s ();
  if (ON) begin : g
    cfg_tr c ();
  end
  if (ON2) begin : g2
    cfg_tr c ();
  end
  if (ON3) begin : g3
    cfg_tr c ();
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
  holder_x hxu ();
  holder_x hxv ();
  holder_xe hxe1 ();
  holder_xe hxe2 ();
  holder_tr htr1 ();
  holder_tr htr2 ();
endmodule
