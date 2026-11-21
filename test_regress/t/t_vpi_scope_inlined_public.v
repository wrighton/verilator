// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Only the inlined scopes above public variables become VPI scopes

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  initial begin
    $write("*-* All Finished *-*\n");
    $finish;
  end

  bank u_bank ();

  wrap u_wrap ();

endmodule

// Many inlined scopes with no public variable under them, inlined into the top scope
module bank;
  for (genvar i = 0; i < 8; ++i) begin : g_hidden
    leaf u_leaf ();
  end
endmodule

module leaf;
  if (1) begin : b_leaf
    // Not constant, so these scopes are kept
    int hidden;
    initial hidden = $test$plusargs("hidden") ? 2 : 1;
    final `checkd(hidden, 1);
  end
endmodule

// Inlined scopes above public variables, in a scope and in the scopes above it
module wrap;
  /*verilator no_inline_module*/
  sub u_first ();
  for (genvar i = 0; i < 2; ++i) begin : g_shown
    if (i == 1) begin : g_one
      sub u_sub ();
    end
  end
endmodule

module sub;
  /*verilator no_inline_module*/
  if (1) begin : b_sub
    logic shown  /*verilator public_flat_rw*/;
    initial shown = 1'b1;
  end
endmodule
