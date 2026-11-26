// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  int calls = 0;
  function automatic bit [3:0] next_value(input bit [3:0] value);
    ++calls;
    return value;
  endfunction

  bit [3:0] v;
  bit signed [3:0] s;
  bit r1, r2, r3, r4;
  initial begin
    r1 = v inside {9'd300, 2'd1};
    r2 = v inside {[2'd0 : 9'd300]};
    r3 = s inside {[-8'sd3 : 3'sd2], 5'd7};
    r4 = next_value(v) inside {9'd300};
  end
endmodule
