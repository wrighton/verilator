// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf;
endmodule

interface probe_if;
endinterface

module t;
  leaf u_leaf1 ();
  leaf #(1) u_leaf2 ();  // Bad: no parameter to override
endmodule

bind t.u_leaf1 probe_if u_probe ();
