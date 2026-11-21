// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface inner_if;
  logic [6:0] data;
endinterface

interface outer_if;
  inner_if child ();
  modport mp(output .write_data(child.data));
endinterface

module t;
  outer_if outer ();
  initial begin
    automatic virtual outer_if.mp vif = outer;
    vif.write_data = '1;
  end
endmodule
