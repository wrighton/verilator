// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

interface ev_if;
  event e;
endinterface

module t;
  ev_if eif ();
  virtual ev_if vif = eif;

  initial begin
    ->vif.e;
    $finish;
  end
endmodule
