// DESCRIPTION: Verilator: Assertion control scope named through a class type with a dot
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A class member is named with '::', not '.', so pk.tk names no scope through the class pk
// (IEEE 1800-2023 8.23, 23.7.1)
module mid;
  initial $assertoff(0, pk.tk);
endmodule

module qar;
  class pk;
    static task tk();
      check : assert (1'b1);
    endtask
  endclass
  mid m ();
  initial $assertoff(0, pk.tk);
endmodule

module par;
  if (1) begin : pk
    if (1) begin : tk
      initial check : assert (1'b1);
    end
  end
  mid m ();
endmodule

module t;
  qar q ();
  par p ();
endmodule
