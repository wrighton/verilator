// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  typedef int da_t[];
  // Typed formal of an aggregate type, of another type than the actual
  let H(da_t a) = 30 + a[0];

  byte dyn[] = '{1, 2};

  initial begin
    if (H(dyn) != (30 + 1)) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
