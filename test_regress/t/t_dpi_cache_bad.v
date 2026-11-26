// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // Unsupported on tasks and exports
  import "DPI-C" task dpic_task(input int a)  /*verilator dpi_cache*/;
  export "DPI-C" function dpix_func  /*verilator dpi_cache*/;
  function int dpix_func(input int a);
    return a;
  endfunction
  initial dpic_task(1);
endmodule
