// DESCRIPTION: Verilator: Generate-if with a condition of unknown value
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module sub #(
    parameter logic P = 1'b1
);
  if (P) begin : g_p
    localparam int TAKEN = 1;
  end else begin : g_p
    localparam int TAKEN = 0;
  end
endmodule

module t;
  localparam logic UNKNOWN = 1'bx;
  localparam logic FLOATING = 1'bz;
  localparam logic [3:0] PARTLY_ONE = 4'b1x0x;
  localparam logic [3:0] NO_ONE = 4'b0x0z;
  localparam int OUTSIDE = 4;

  // A condition with no known one bit is false, as for a procedural if
  if (UNKNOWN) begin : g_unknown
    localparam int TAKEN = 1;
  end else begin : g_unknown
    localparam int TAKEN = 0;
  end
  if (!UNKNOWN) begin : g_not_unknown
    localparam int TAKEN = 1;
  end else begin : g_not_unknown
    localparam int TAKEN = 0;
  end
  if (FLOATING) begin : g_floating
    localparam int TAKEN = 1;
  end else begin : g_floating
    localparam int TAKEN = 0;
  end
  if (|NO_ONE) begin : g_no_one
    localparam int TAKEN = 1;
  end else begin : g_no_one
    localparam int TAKEN = 0;
  end
  // A known one bit makes the condition true
  if (|PARTLY_ONE) begin : g_partly_one
    localparam int TAKEN = 1;
  end else begin : g_partly_one
    localparam int TAKEN = 0;
  end
  // Selects of an unknown bit, of bits with a known one, and outside the vector
  if (PARTLY_ONE[2]) begin : g_select_unknown
    localparam int TAKEN = 1;
  end else begin : g_select_unknown
    localparam int TAKEN = 0;
  end
  if (|PARTLY_ONE[3:2]) begin : g_select_one
    localparam int TAKEN = 1;
  end else begin : g_select_one
    localparam int TAKEN = 0;
  end
  // verilator lint_off SELRANGE
  if (PARTLY_ONE[OUTSIDE]) begin : g_select_outside
    localparam int TAKEN = 1;
  end else begin : g_select_outside
    localparam int TAKEN = 0;
  end
  // verilator lint_on SELRANGE
  // An else-if chain continues past an unknown condition
  if (UNKNOWN) begin : g_chain_first
    localparam int TAKEN = 1;
  end else if (1'b1) begin : g_chain_first
    localparam int TAKEN = 2;
  end else begin : g_chain_first
    localparam int TAKEN = 3;
  end
  if (1'b0) begin : g_chain_last
    localparam int TAKEN = 1;
  end else if (UNKNOWN) begin : g_chain_last
    localparam int TAKEN = 2;
  end else begin : g_chain_last
    localparam int TAKEN = 3;
  end
  // Inside a generate block and a generate loop
  if (1'b1) begin : g_outer
    if (UNKNOWN) begin : g_inner
      localparam int TAKEN = 1;
    end else begin : g_inner
      localparam int TAKEN = 0;
    end
  end
  for (genvar i = 0; i < 2; ++i) begin : g_loop
    if (PARTLY_ONE[i]) begin : g_bit
      localparam int TAKEN = 1;
    end else begin : g_bit
      localparam int TAKEN = 0;
    end
  end
  // Equality with an unknown value is unknown, case equality is known
  if (UNKNOWN == 1'bx) begin : g_equal
    localparam int TAKEN = 1;
  end else begin : g_equal
    localparam int TAKEN = 0;
  end
  if (UNKNOWN === 1'bx) begin : g_case_equal
    localparam int TAKEN = 1;
  end else begin : g_case_equal
    localparam int TAKEN = 0;
  end
  // Case-generate is unchanged: it compares with case equality
  case (UNKNOWN)
    FLOATING: begin : g_case
      localparam int TAKEN = 2;
    end
    UNKNOWN: begin : g_case
      localparam int TAKEN = 1;
    end
    default: begin : g_case
      localparam int TAKEN = 0;
    end
  endcase
  // A parameter overridden with an unknown value
  sub u_default ();
  sub #(.P(1'bx)) u_unknown ();

  initial begin
    `checkd(g_unknown.TAKEN, 0);
    `checkd(g_not_unknown.TAKEN, 0);
    `checkd(g_floating.TAKEN, 0);
    `checkd(g_no_one.TAKEN, 0);
    `checkd(g_partly_one.TAKEN, 1);
    `checkd(g_select_unknown.TAKEN, 0);
    `checkd(g_select_one.TAKEN, 1);
    `checkd(g_select_outside.TAKEN, 0);
    `checkd(g_chain_first.TAKEN, 2);
    `checkd(g_chain_last.TAKEN, 3);
    `checkd(g_outer.g_inner.TAKEN, 0);
    `checkd(g_loop[0].g_bit.TAKEN, 0);
    `checkd(g_loop[1].g_bit.TAKEN, 0);
    `checkd(g_equal.TAKEN, 0);
    `checkd(g_case_equal.TAKEN, 1);
    `checkd(g_case.TAKEN, 1);
    `checkd(u_default.g_p.TAKEN, 1);
    `checkd(u_unknown.g_p.TAKEN, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
  // Without an else, nothing is generated
  if (UNKNOWN) begin : g_no_else
    $error("generated a block for an unknown condition");
  end
endmodule
