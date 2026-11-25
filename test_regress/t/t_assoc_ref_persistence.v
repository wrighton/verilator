// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

localparam int N = 4096;

// Deleting an associative array element passed by reference leaves it as an outdated
// reference, and references to the other elements bound (IEEE 1800-2023 13.5.2), also without
// timing
class Holder;
  int aa[int];
  function void bump(ref int removed, ref int survivor);
    aa.delete(0);
    aa[0] = 5;  // A new element, likely where the removed one was freed without the fix
    removed = -7;
    survivor = -42;
  endfunction
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic int expected = -42;
`ifdef VERILATOR
    // Before C++17, deleting an element passed by reference outdates every reference into
    // the array, so the write to the remaining element is not seen
    if ($c32("__cplusplus < 201703L")) expected = 3000;
`endif
`ifdef TEST_CXX14
    `checkd($c32("__cplusplus < 201703L"), 1);
`endif
    for (int j = 0; j < N; ++j) h.aa[j] = j;
    h.bump(h.aa[0], h.aa[3000]);
    `checkd(h.aa.size(), N);
    `checkd(h.aa[0], 5);
    `checkd(h.aa[3000], expected);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
