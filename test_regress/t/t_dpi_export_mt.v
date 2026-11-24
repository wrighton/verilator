// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  int cnt = 0;

  sub s ();

  export "DPI-C" function dpix_count;
  function int dpix_count();
    return cnt;
  endfunction

  import "DPI-C" context function void dpii_tick();

  always @(posedge clk) begin
    cnt <= cnt + 1;
    dpii_tick();
  end
endmodule

module sub;
  // Called from the scope of 't', so found as the only export of its name
  export "DPI-C" function dpix_sub;
  function int dpix_sub();
    return 5;
  endfunction
endmodule
