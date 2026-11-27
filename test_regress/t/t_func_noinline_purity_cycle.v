// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Pure cycles of non-inlined calls, mutual and direct, and a caller of each
module t (
    input clk
);
  // verilog_format: off
  function automatic bit is_even(int n); /*verilator no_inline_task*/
    return (n == 0) ? 1'b1 : is_odd(n - 1);
  endfunction
  function automatic bit is_odd(int n); /*verilator no_inline_task*/
    return (n == 0) ? 1'b0 : is_even(n - 1);
  endfunction
  function automatic int fact(int n); /*verilator no_inline_task*/
    return (n <= 1) ? 1 : n * fact(n - 1);
  endfunction
  function automatic int parity_fact(int n); /*verilator no_inline_task*/
    return is_even(n) ? fact(n) : -fact(n);
  endfunction
  // verilog_format: on
  int cyc = 0;
  int sig = 0;
  int seen = 0;
  // Pure, so allowed in a sensitivity list
  always @(parity_fact(sig)) seen = seen + 1;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    sig <= cyc;
    if (cyc == 9) begin
      if (parity_fact(3) != -6) $stop;
      if (parity_fact(4) != 24) $stop;
      if (seen == 0) $stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
