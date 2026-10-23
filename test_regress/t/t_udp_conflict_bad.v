// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 29.3.4: Lines with the same inputs, including edges,
// shall not specify different outputs

primitive p_comb (o, a, b);
  output o;
  input a, b;
  table
    1 ? : 1;
    ? 1 : 0;  // <--- BAD: '1 1' conflicts
    0 b : 0;  // Overlaps '0 1' with the same output
    x 0 : x;  // 'b' does not match 'x'
    ? x : 1;
    x ? : 0;  // <--- BAD: 'x 0' conflicts
  endtable
endprimitive

primitive p_seq (q, c, d);
  output q;
  reg q;
  input c, d;
  table
    r 0 : ? : 0;
    (0?) 0 : ? : 1;  // <--- BAD: '(01) 0' conflicts
    F ? : ? : -;
    (?0) 1 : ? : 0;  // <--- BAD: '(10) 1' with current output 1 conflicts
    ? 1 : ? : 1;  // Level line, takes precedence over edge lines
    0 R : ? : 1;  // Edge on another input
    0 p : 1 : -;  // No change gives the same output as '0 R' above
    0 (X1) : 0 : -;
    0 * : 0 : 1;  // <--- BAD: '0 (x1)' with current output 0 conflicts
    1 0 : 0 : 0;
    1 0 : B : 1;  // <--- BAD: '1 0' with current output 0 conflicts
    1 n : ? : 0;
    1 P : ? : 1;  // 'p' does not overlap 'n'
    1 (x0) : ? : 1;  // <--- BAD: '1 (x0)' conflicts with 'n'
  endtable
endprimitive

module t (
    input a,
    input b,
    output o,
    output q
);
  p_comb u_comb (o, a, b);
  p_seq u_seq (q, a, b);
endmodule
