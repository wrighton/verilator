// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  int v;
endclass

class Holder;
  Cls m;
  function int g();
    return $sampled(m.v);
  endfunction
endclass

module t;
  Holder hld = new;
endmodule
