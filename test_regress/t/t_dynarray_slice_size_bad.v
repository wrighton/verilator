// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  initial begin
    byte d[];
    byte s3[3];
    int i;
    d = new[4];
    d[0:1] = '{1, 2, 3};  // Error: 2 elements assigned 3
    d[1:3] = '{1, 2};  // Error: 3 elements assigned 2
    d[i+:2] = {s3[0], 1, 2};  // Error: 2 elements assigned 3
    d[i-:3] = s3[0:1];  // Error: 3 elements assigned 2
    d[0:2] = s3;
    d[0:1] = {s3[0], 5};
    d[0:3] = {5, s3};
    d[0:2] = {5, d};  // Checked at run time
    d[0:1] = '{0: 5, 1: 6};  // Checked at run time
  end
endmodule
