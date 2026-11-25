// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Instances given the same parameter values by defparams share a specialization.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module leaf #(
    parameter int P = 0
) (
    output int o
);
  assign o = P;
endmodule

module holder (
    output int o
);
  leaf x (.o(o));
endmodule

module mid (
    output int o
);
  leaf s (.o(o));
  defparam s.P = 5;
endmodule

module t;
  // Holders given the same constant share a specialization, one given another does not
  int oc;
  int od;
  int oe;
  holder c (.o(oc));
  holder d (.o(od));
  holder e (.o(oe));
  defparam c.x.P = 7;
  defparam d.x.P = 7;
  defparam e.x.P = 8;
  initial begin
    #1;
    `checkd(oc, 7);
    `checkd(od, 7);
    `checkd(oe, 8);
  end

  // Holders given the same value that is not a constant each have their own specialization
  localparam int K = 3;
  int of;
  int og;
  holder f (.o(of));
  holder g (.o(og));
  defparam f.x.P = K;
  defparam g.x.P = K;
  initial begin
    #1;
    `checkd(of, 3);
    `checkd(og, 3);
  end

  // A defparam inside a module gives all its instances the same value
  int om[4];
  for (genvar i = 0; i < 4; ++i) begin : gm
    mid m (.o(om[i]));
  end
  initial begin
    #1;
    for (int i = 0; i < 4; ++i) `checkd(om[i], 5);
  end

  initial begin
    #2;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
