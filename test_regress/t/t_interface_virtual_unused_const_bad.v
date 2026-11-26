// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface QBus;
  // A constant function cannot use a hierarchical name (IEEE 1800-2023 13.4.3)
  function automatic int width();
    return missing_inst.w;
  endfunction
  localparam int W = width();
  logic [W-1:0] data;
endinterface

module t;
  virtual QBus vif;
endmodule
