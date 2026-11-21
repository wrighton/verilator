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
  leaf u_leaf ();
endmodule

bind leaf probe_if u_probe ();
bind leaf probe_if u_probe ();  // Bad: duplicate in every instance
