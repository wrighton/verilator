// DESCRIPTION: Verilator: Verilog Test module
//
// A ref argument of a queue with another bound than the connection is
// unsupported, though the types are equivalent (IEEE 1800-2023 6.22.2).
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef bit [1:0][3:0] split_t;

  function automatic void f_split(ref split_t q[$:1]);
  endfunction
  function automatic void f_byte(ref byte unsigned q[$]);
  endfunction

  initial begin
    bit [7:0] q4[$:4];
    byte unsigned q1[$:1];
    f_split(q4);  // Equivalent elements, another bound
    f_byte(q1);  // Bounded and unbounded
  end
endmodule
