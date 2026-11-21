// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Nested selects of a dynamic array, each with an index wider than 32 bits

module t;
  initial begin
    typedef bit [32:0] wide_dyn_t[];
    automatic wide_dyn_t d = new[5];
    automatic bit [32:0] idx;
    automatic bit [32:0] got;
    foreach (d[k]) d[k] = 33'((k + 1) % d.size());
    for (int k = 0; k < d.size(); k++) begin
      idx = 33'(k);
      got = d[d[d[d[d[d[d[d[d[d[d[d[idx]]]]]]]]]]]];
      `checkd(got, (k + 12) % 5);
      // Out of range, so the innermost select reads 0
      idx = {1'b1, 32'(k)};
      got = d[d[d[d[d[d[d[d[d[d[d[d[idx]]]]]]]]]]]];
      `checkd(got, 11 % 5);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
