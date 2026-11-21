// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  rand int q[2];
  constraint c_q {foreach (q[q]) q[q] < 5;}  // loop variable same as array
endclass

module t;

  integer a, b;

  reg [2:0][2:0] array;

  initial begin
    foreach (array);  // no index

    foreach (array.array[a]);  // not supported

    foreach (array[a.b]);  // no index

    foreach (array[array]);  // loop variable same as array

    foreach (array[a, array]);  // loop variable same as array

    foreach (array[1][array]);  // loop variable same as array

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
