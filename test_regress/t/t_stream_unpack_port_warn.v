// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A stream sized at run time connected to an unpacked array input port, wider
// than the port, is an error warned at run time (IEEE 1800-2023 11.4.14,
// 23.3.3).

module recv (
    input bit [7:0] ia[2]
);
endmodule

module t;
  byte q[$];
  recv u (.ia({>>{8'h12, q}}));
  initial begin
    q = '{8'h34, 8'h56};  // Bad: 24 bits into 16
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
