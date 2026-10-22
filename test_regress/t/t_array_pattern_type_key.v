// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Data type keys in array assignment patterns (IEEE 1800-2023 10.9.1)
module t;

  typedef int int_t;

  int arr[4] = '{1: 9, int: 7};
  int_t arr_typedef[3:1] = '{2: 1, int: 2};
  // An index key takes precedence over a data type key, which takes precedence over default
  byte arr_default[4] = '{0: 8'd1, byte: 8'd2, default: 8'd3};
  // A data type key not matching the element type does not apply
  byte arr_unmatched[2] = '{int: 5, default: 8'd4};
  // Data type keys apply to the elements of aggregate elements through default
  int arr_nested[2][3] = '{int: 6, default: 0};
  bit [6:0] vec = '{3: 1'b1, bit: 1'b0};
  logic [4:0] vec4 = '{logic: 1'b1};
  shortint packed_elems[2:0] = '{0: 16'h11, shortint: 16'h22};

  initial begin
    `checkh(arr[0], 7);
    `checkh(arr[1], 9);
    `checkh(arr[2], 7);
    `checkh(arr[3], 7);
    `checkh(arr_typedef[3], 2);
    `checkh(arr_typedef[2], 1);
    `checkh(arr_typedef[1], 2);
    `checkh(arr_default[0], 8'd1);
    `checkh(arr_default[1], 8'd2);
    `checkh(arr_default[3], 8'd2);
    `checkh(arr_unmatched[0], 8'd4);
    `checkh(arr_unmatched[1], 8'd4);
    foreach (arr_nested[i, j]) `checkh(arr_nested[i][j], 6);
    `checkh(vec, 7'b0001000);
    `checkh(vec4, 5'b11111);
    `checkh(packed_elems[2], 16'h22);
    `checkh(packed_elems[0], 16'h11);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
