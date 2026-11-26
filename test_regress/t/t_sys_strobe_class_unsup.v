// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class C;
  int v;
  function void strobe();
    $strobe("v=%0d", v);  // Unsup
  endfunction
  function void monitor();
    $monitor("v=%0d", v);  // Unsup
  endfunction
  function int get();
    return v;
  endfunction
  function int one();
    return 1;
  endfunction
  function void calls();
    $strobe("get=%0d one=%0d", get(), one());  // Unsup
    $strobe("this=%p", this);  // Unsup
  endfunction
  rand int x;
  constraint cx {x < 10;}
  function void modes();
    $strobe("%0d %0d", cx.constraint_mode(), x.rand_mode());  // Unsup
  endfunction
endclass

module t;
endmodule
