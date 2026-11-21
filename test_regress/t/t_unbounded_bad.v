// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  initial begin
    if ($) $stop;
  end
  sub u (.a($));  // '$' is only allowed as a parameter value
endmodule

module sub (
    input int a
);
endmodule
