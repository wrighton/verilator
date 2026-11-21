// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf;
endmodule

interface probe_if;
endinterface

module sub;
  for (genvar i = 0; i < 2; ++i) begin : gen
    leaf u_leaf ();
  end
  bind gen[2].u_leaf probe_if u_probe ();  // Bad: no such iteration
endmodule

module t;
  sub u_sub ();
endmodule

bind t.u_sub.gen[5].u_leaf probe_if u_probe ();  // Bad: no such iteration
