// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module a (
    in,
    out
);
  input in;
  output out;
  assign out = !in;
  sub sub ();
  initial $display("In '%m'");
endmodule

module b (
    in,
    out
);
  input in;
  output out;
  assign out = in;
  sub sub ();
  initial $display("In '%m'");
endmodule

module c (
    uniq_in,
    uniq_out
);
  input uniq_in;
  output uniq_out;
  assign uniq_out = !uniq_in;
  sub sub ();
  initial $display("In '%m'");
endmodule

package d_pkg;
  localparam int W = 1;
endpackage

// Ports named like the instances of top modules and packages
module d (
    a,
    d_pkg,
    d
);
  input a;
  input [d_pkg::W-1:0] d_pkg;
  output d;
  assign d = a ^ d_pkg;
  sub sub ();
  initial $display("In '%m'");
endmodule

module sub;
  initial $display("In '%m'");
endmodule
