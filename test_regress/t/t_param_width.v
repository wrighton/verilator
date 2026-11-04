// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2016 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// See issue #1991

class Cls #(
    ADDR = 2
);
endclass

interface ifc #(
    ADDR = 2
);
endinterface

module t (
    input clk
);

  socket #(3'b000) s0 ();
  socket #(3'b010) s1 ();
  socket #(2'b10) s2 ();
  socket #(2'b11) s3 ();

  // Untyped parameters overridden by a value equal to the default, of another type
  socket_default #(.ADDR(2'd2)) d0 ();
  socket_default #(.SIGNED(4'sb1111)) d1 ();
  socket_default d2 ();
  ifc #(.ADDR(2'd2)) i0 ();

  // An equal value of the same width and signedness is the default
  localparam int W = 2;
  localparam bit signed [31:0] WB = 2;
  Cls #(W) cls_w = new;
  Cls #() cls_dflt = cls_w;
  Cls #(WB) cls_wb = cls_w;

  always_ff @(posedge clk) begin
    if (s0.ADDR != 0) $stop;
    if (s1.ADDR != 2) $stop;
    if (s2.ADDR != 2) $stop;
    if (s3.ADDR != 3) $stop;
    if ($bits(s0.ADDR) != 3) $stop;
    if ($bits(s1.ADDR) != 3) $stop;
    if ($bits(s2.ADDR) != 2) $stop;
    if ($bits(s3.ADDR) != 2) $stop;
    if ($bits(d0.ADDR) != 2) $stop;
    if ($bits(d2.ADDR) != 32) $stop;
    if (d1.SIGNED >= 0) $stop;
    if (d2.SIGNED <= 0) $stop;
    if ($bits(Cls#(2'd2)::ADDR) != 2) $stop;
    if ($bits(Cls#()::ADDR) != 32) $stop;
    if ($bits(i0.ADDR) != 2) $stop;
    if (cls_dflt != cls_w) $stop;
    if (cls_wb != cls_w) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule

module socket #(
    ADDR
) ();
  initial $display("bits %0d, addr %b", $bits(ADDR), ADDR);
endmodule

module socket_default #(
    ADDR = 2,
    SIGNED = 4'b1111
) ();
endmodule
