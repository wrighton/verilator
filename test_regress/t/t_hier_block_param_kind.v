// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // The untyped parameter is 32 bits wide for 5, but 8 bits for 8'd5, also relative to the
  // default value
  int width_5, width_8d5, width_8d0;
  longint value_5, value_8d5, value_8d0;
  mid #(.P(5)) m_5 (
      .width(width_5),
      .value(value_5)
  );
  mid #(.P(8'd5)) m_8d5 (
      .width(width_8d5),
      .value(value_8d5)
  );
  mid #(.P(8'd0)) m_8d0 (
      .width(width_8d0),
      .value(value_8d0)
  );
  initial begin
    #1;
    `checkd(width_5, 32);
    `checkd(value_5, 5);
    `checkd(width_8d5, 8);
    `checkd(value_8d5, 5);
    `checkd(width_8d0, 8);
    `checkd(value_8d0, 0);
  end

  // Signedness differs likewise
  bit sgn_8sd5, sgn_8d5b, sgn_32d5;
  mid_sgn #(.P(8'sd5)) m_8sd5 (.sgn(sgn_8sd5));
  mid_sgn #(.P(8'd5)) m_8d5b (.sgn(sgn_8d5b));
  mid_sgn #(.P(32'd5)) m_32d5 (.sgn(sgn_32d5));
  initial begin
    #1;
    `checkd(sgn_8sd5, 1'b1);
    `checkd(sgn_8d5b, 1'b0);
    `checkd(sgn_32d5, 1'b0);
  end

  // An unbased unsized value is 1 bit wide, as is 1'b1
  int width_ones, width_1b1;
  longint value_ones, value_1b1;
  mid #(.P('1)) m_ones (
      .width(width_ones),
      .value(value_ones)
  );
  mid #(.P(1'b1)) m_1b1 (
      .width(width_1b1),
      .value(value_1b1)
  );
  initial begin
    #1;
    `checkd(width_ones, 1);
    `checkd(value_ones, 1);
    `checkd(width_1b1, 1);
    `checkd(value_1b1, 1);
  end

  // An integral value for a real default, and a real value for an integral default
  int width_int, width_real;
  longint value_int, value_real;
  mid_real #(.P(1)) m_int (
      .width(width_int),
      .value(value_int)
  );
  mid #(.P(2.5)) m_real (
      .width(width_real),
      .value(value_real)
  );
  initial begin
    #1;
    `checkd(width_int, 32);
    `checkd(value_int, 1);
    `checkd(width_real, 64);
    `checkd(value_real, 3);
  end

  // A value relative to a default value that is an expression
  int width_q;
  longint value_q;
  mid_q #(.Q(4'd9)) m_q (
      .width(width_q),
      .value(value_q)
  );
  initial begin
    #1;
    `checkd(width_q, 4);
    `checkd(value_q, 9);
  end

  // A comparison is 1 bit wide, both when equal and when not equal to the default value
  int width_real_mode, width_bypass;
  longint value_real_mode, value_bypass;
  wrap #(.MODE("REAL")) w_real (
      .width(width_real_mode),
      .value(value_real_mode)
  );
  wrap #(.MODE("BYPASS")) w_bypass (
      .width(width_bypass),
      .value(value_bypass)
  );
  initial begin
    #1;
    `checkd(width_real_mode, 1);
    `checkd(value_real_mode, 0);
    `checkd(width_bypass, 1);
    `checkd(value_bypass, 1);
  end

  initial begin
    #2;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module wrap #(
    parameter string MODE = "REAL"
) (
    output int width,
    output longint value
);
  mid #(.P(MODE == "BYPASS")) u (
      .width(width),
      .value(value)
  );
endmodule

module mid #(
    parameter P = 0
) (
    output int width,
    output longint value
);
  /*verilator hier_block*/
  assign width = $bits(P);
  assign value = longint'(P);
endmodule

module mid_sgn #(
    parameter P = 0
) (
    output bit sgn
);
  /*verilator hier_block*/
  assign sgn = ((P - P - 1) >>> 1) == (P - P - 1);
endmodule

module mid_real #(
    parameter P = 1.0
) (
    output int width,
    output longint value
);
  /*verilator hier_block*/
  assign width = $bits(P);
  assign value = longint'(P);
endmodule

module mid_q #(
    parameter P = 0,
    parameter Q = P + 1
) (
    output int width,
    output longint value
);
  /*verilator hier_block*/
  assign width = $bits(Q);
  assign value = longint'(Q);
endmodule
