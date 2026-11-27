// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  task automatic tauto(input int z);
    $monitor("z=%0d", z);  // Bad
  endtask
  class C;
    static function void fmethod(int x);
      $monitor("x=%0d", x);  // Bad
    endfunction
  endclass
  initial begin
    tauto(8);
    C::fmethod(9);
  end
endmodule
