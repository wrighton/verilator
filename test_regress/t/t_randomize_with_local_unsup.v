// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  rand Cls h;
  function int rand_this(Cls other);
    return other.randomize() with { h == local::this; };
  endfunction
endclass

module t;
endmodule
