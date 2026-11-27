// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  default clocking @(posedge clk);
  endclocking

  class C;
    int v;
    function int pastv();
      return $past(v);  // Unsup
    endfunction
    function int sampledv();
      return $sampled(v);  // Unsup
    endfunction
    // Explicitly clocked, and never called
    function int pastclk();
      return $past(v, 1,, @(posedge clk));  // Unsup
    endfunction
    function bit roseclk();
      return $rose(v, @(posedge clk));  // Unsup
    endfunction
    function bit stableclk();
      return $stable(v, @(posedge clk));  // Unsup
    endfunction
  endclass
endmodule
