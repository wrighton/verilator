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
  for (genvar g = 0; g < 2; ++g) begin : gen
    leaf u_leaf ();
  end
  if (1) begin : g_if
    leaf u_leaf ();
  end
  leaf u_leaf ();
endmodule

bind t.gen[0].u_lef probe_if u_probe ();  // Bad: no such instance
bind nosuch.u_leaf probe_if u_probe ();  // Bad: no such instance or module
bind t.gen[0] probe_if u_probe ();  // Bad: a generate block, not an instance
bind t.gen.u_leaf probe_if u_probe ();  // Bad: no generate loop index
bind t.g_if[0].u_leaf probe_if u_probe ();  // Bad: not a generate loop
bind t.u_leaf[0] probe_if u_probe ();  // Bad: not an instance array
