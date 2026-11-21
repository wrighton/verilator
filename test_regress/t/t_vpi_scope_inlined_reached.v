// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Only the inlined instances and named blocks above variables VPI can reach are kept

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

  forced u_forced ();

endmodule

// Many inlined instances and named blocks with no variable VPI can reach
module bank;
  for (genvar i = 0; i < 8; ++i) begin : g_hidden
    leaf u_leaf ();
  end
endmodule

module leaf;
  if (1) begin : b_leaf
    // Not constant, so these instances are kept
    int hidden;
    initial hidden = $test$plusargs("hidden") ? 2 : 1;
    final `checkd(hidden, 1);
  end
endmodule

// Inlined instances and named blocks above a public variable
module wrap;
  for (genvar i = 0; i < 2; ++i) begin : g_shown
    if (i == 1) begin : g_one
      sub u_sub ();
    end
  end
endmodule

module sub;
  if (1) begin : b_sub
    logic shown  /*verilator public_flat_rw*/;
    initial shown = 1'b1;
  end
endmodule

// A forceable variable is reached through its public force controls
module forced;
  if (1) begin : b_forced
    logic value  /*verilator forceable*/;
    initial value = 1'b0;
  end
endmodule
