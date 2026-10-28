// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  let G(int a[2]) = 30 + a[0];
  let H(signed a[2]) = 30 + a[0];

  initial begin
    int arr[2] = '{1, 2};
    if (G(arr) != (30 + 1)) $stop;
    if (H(arr) != (30 + 1)) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
