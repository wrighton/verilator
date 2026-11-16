// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls #(
    parameter PARAMB = 12
);
endclass

module sub #(
    type T = int
);
endmodule

module t;

  Cls #(.PARAMBAD(1)) c;  // Bad param name
  Cls #(13, 1) cd;  // Bad param number

  if (1) begin : g
    Cls #(.PARAMBAD(2)) gc;  // Bad param name, in generate block
    sub #(.T(Cls#(.PARAMBAD(3)))) u_sub ();  // Bad param name, in generate block instance
  end

endmodule
