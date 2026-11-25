// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A call of a DPI import marked /*verilator dpi_cache*/ with the inputs of the previous call of
// the same instance reuses its outputs; one with an inout or open array argument calls again

`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

module t;
  import "DPI-C" function int dpic_sum(input int a, input int arr[2], output int calls)
      /*verilator dpi_cache*/;
  import "DPI-C" function int dpic_inout(inout int a)  /*verilator dpi_cache*/;
  import "DPI-C" function int dpic_open(input int arr[])  /*verilator dpi_cache*/;
  import "DPI-C" function int dpic_decl(input int a)
      /*verilator dpi_c_decl "int dpic_decl(int)"*/  /*verilator dpi_cache*/;

  int arr[2] = '{1, 2};
  int open_arr[2] = '{3, 4};
  int calls;
  int a;
  int r;

  initial begin
    r = dpic_sum(10, arr, calls);
    `checkh(r, 13);
    `checkh(calls, 1);
    // Same inputs: reused, including the output
    calls = 0;
    r = dpic_sum(10, arr, calls);
    `checkh(r, 13);
    `checkh(calls, 1);
    arr[1] = 5;
    r = dpic_sum(10, arr, calls);
    `checkh(r, 16);
    `checkh(calls, 2);
    // Inout and open array arguments call again
    a = 1;
    r = dpic_inout(a);
    r = dpic_inout(a);
    `checkh(r, 2);
    `checkh(a, 3);
    r = dpic_open(open_arr);
    r = dpic_open(open_arr);
    `checkh(r, 2);
    // With a C declaration too
    r = dpic_decl(7);
    r = dpic_decl(7);
    `checkh(r, 701);
    r = dpic_decl(8);
    `checkh(r, 802);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
