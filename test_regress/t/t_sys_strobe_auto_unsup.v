// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  function void fstatic(int y);
    $strobe("y=%0d", y);  // Unsup
  endfunction
  function automatic void fauto();
    int z = 4;
    $strobe("z=%0d", z);  // Unsup
  endfunction
  task tstatic(input int w);
    $monitor("w=%0d", w);  // Unsup
  endtask
  initial begin
    fstatic(1);
    fauto();
    tstatic(2);
  end
endmodule
