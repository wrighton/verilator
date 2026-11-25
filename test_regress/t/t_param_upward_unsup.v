// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

module t;
  mid #(.LSB(0), .UNTYPED(8'd3)) m0 ();
  mid #(.LSB(1), .UNTYPED(16'd5)) m1 ();
  mid #(.LSB(2), .UNTYPED(32'd7)) m2 ();
  same #(.W(8), .UNTYPED(8'd3)) s8 ();
  same #(.W(16), .UNTYPED(16'd3)) s16 ();
  zero_ext #(.W(4)) z4 ();
  zero_ext #(.W(8)) z8 ();
endmodule

module mid #(
    parameter int LSB = 0,
    parameter UNTYPED = 0
);
  localparam logic [LSB+6:LSB] RANGED = '1;
  typedef enum int {
    A = LSB,
    B
  } enum_t;
  localparam enum_t ENUMED = B;
  leaf l ();
endmodule

module leaf;
  int ranged;
  int sized;
  int enumed;
  initial begin
    ranged = int'(mid.RANGED[2]);  // Bounds differ
    sized = int'(mid.UNTYPED);  // Width differs
    enumed = int'(mid.ENUMED);  // Enum items differ
  end
endmodule

// Equal values, but the width differs, which a concatenation uses
module same #(
    parameter int W = 8,
    parameter UNTYPED = 0
);
  localparam logic [W-1:0] TYPED = 3;
  same_reader r ();
endmodule

module same_reader;
  logic [31:0] typed_cat;
  logic [31:0] untyped_cat;
  initial begin
    typed_cat = 32'({8'h01, same.TYPED});
    untyped_cat = 32'({8'h01, same.UNTYPED});
  end
endmodule

// Signed values, equal once sign extended, but read zero extended
module zero_ext #(
    parameter int W = 4
);
  localparam logic signed [W-1:0] NEGATIVE = -1;
  zero_ext_reader r ();
endmodule

module zero_ext_reader;
  int unsigned_add;
  int unsigned_cast;
  initial begin
    unsigned_add = zero_ext.NEGATIVE + 32'd0;
    unsigned_cast = 32'(unsigned'(zero_ext.NEGATIVE));
  end
endmodule
