// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// Upwards references (IEEE 1800-2023 23.8) from a module under one instance shared by two
// specializations of a wrapper

module t;
  wrapper #(.P(3)) a ();
  wrapper #(.P(5)) b ();
  wide_wrapper #(.P(4'd3)) wa ();
  wide_wrapper #(.P(8'd5)) wb ();
endmodule

module leaf;
  int got;
  initial got = mid.read();  // Default value differs
endmodule

module mid #(
    parameter int P = 3
);
  function automatic int read(input int v = P);
    return v;
  endfunction
  leaf l ();
endmodule

module wrapper #(
    parameter int P = 3
);
  mid #(.P(P)) m ();
endmodule

module wide_leaf;
  int sized;
  int got;
  initial begin
    sized = int'(wide_mid.P);  // Width differs
    got = wide_mid.read();  // Default value differs
  end
endmodule

module wide_mid #(
    parameter P = 4'd3
);
  function automatic int read(input int v = int'(P));
    return v;
  endfunction
  wide_leaf l ();
endmodule

module wide_wrapper #(
    parameter P = 4'd3
);
  wide_mid #(.P(P)) m ();
endmodule
