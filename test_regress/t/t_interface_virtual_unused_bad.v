// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface QBus;
  // Needed to elaborate the interface's type, so still reported
  logic [missing_inst.w-1:0] data;
endinterface

module t;
  virtual QBus vif;
endmodule
