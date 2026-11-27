// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // A 'return' at the end of an 'if' that ends an inner block, and so is not at the end of the
  // function
  function automatic int f(int a, int b);
    int r = 1;
    begin : inner
      if (a == 1) disable inner;
      else if (b == 1) return 5;
    end
    r = 7;
    return r;
  endfunction

  int a, b;

  initial begin
    a = $c32("0");
    b = $c32("1");
    `checkd(f(a, b), 5);
    `checkd(f(a + 1, b), 7);
    `checkd(f(a, b + 1), 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
