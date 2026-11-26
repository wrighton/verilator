// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Chains of logical operators with an operand partway that keeps them logical: only the
// parts of the chain without it become bitwise, and the operand is still short-circuited

module t (
    input clk
);
  int cyc = 0;
  int unsigned crc = 32'h5aa5;
  logic [5:0] a;
  logic [7:0] w;
  int n_calls = 0;
  int n_calls_exp = 0;

  function automatic bit f(input bit v);
    ++n_calls;
    return v;
  endfunction

  always @(posedge clk) begin
    bit r_or, r_and, r_wide_or, r_wide_and, r_tree;
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a = crc[5:0];
    w = crc[15:8];
    // Impure operand partway
    r_or = a[0] || a[1] || f(a[2]) || a[3] || a[4];
    if (!(a[0] || a[1])) ++n_calls_exp;
    `checkd(r_or, |a[4:0]);
    r_and = a[0] && a[1] && f(a[2]) && a[3] && a[4];
    if (a[0] && a[1]) ++n_calls_exp;
    `checkd(r_and, &a[4:0]);
    // Wide operand partway
    r_wide_or = a[0] || a[1] || w || a[3] || a[4];
    `checkd(r_wide_or, a[0] | a[1] | (w != 0) | a[3] | a[4]);
    r_wide_and = a[0] && (w && a[1]) && a[3] && a[4];
    `checkd(r_wide_and, a[0] & (w != 0) & a[1] & a[3] & a[4]);
    // Both, in a tree
    r_tree = (a[0] || a[1]) || (f(a[2]) || (a[3] || w)) || (a[4] || a[5]);
    if (!(a[0] || a[1])) ++n_calls_exp;
    `checkd(r_tree, |a | (w != 0));
    `checkd(n_calls, n_calls_exp);
    if (cyc == 40) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
