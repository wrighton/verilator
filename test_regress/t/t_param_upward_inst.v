// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// Upwards references (IEEE 1800-2023 23.8) resolve from each instance, so read the
// declarations of the instance above each

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  mid #(.LSB(0), .UNTYPED(8'd3)) m0 ();
  mid #(.LSB(1), .UNTYPED(16'd5)) m1 ();
  mid #(.LSB(2), .UNTYPED(32'd7)) m2 ();
  same #(.W(8), .UNTYPED(8'd3)) s8 ();
  same #(.W(16), .UNTYPED(16'd3)) s16 ();
  zero_ext #(.W(4)) z4 ();
  zero_ext #(.W(8)) z8 ();

  initial begin
    #1;
    `checkd(m0.l.ranged, 1);
    `checkd(m1.l.ranged, 1);
    `checkd(m2.l.ranged, 1);
    `checkd(m0.l.sized, 3);
    `checkd(m1.l.sized, 5);
    `checkd(m2.l.sized, 7);
    `checkd(m0.l.enumed, 1);
    `checkd(m1.l.enumed, 2);
    `checkd(m2.l.enumed, 3);
    `checkd(s8.r.typed_cat, 32'h103);
    `checkd(s16.r.typed_cat, 32'h10003);
    `checkd(s8.r.untyped_cat, 32'h103);
    `checkd(s16.r.untyped_cat, 32'h10003);
    `checkd(z4.r.unsigned_add, 15);
    `checkd(z8.r.unsigned_add, 255);
    `checkd(z4.r.unsigned_cast, 15);
    `checkd(z8.r.unsigned_cast, 255);
    $write("*-* All Finished *-*\n");
    $finish;
  end
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
    // verilator lint_off WIDTHEXPAND
    unsigned_add = zero_ext.NEGATIVE + 32'd0;
    // verilator lint_on WIDTHEXPAND
    unsigned_cast = 32'(unsigned'(zero_ext.NEGATIVE));
  end
endmodule
