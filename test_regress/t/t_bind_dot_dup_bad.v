// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf;
endmodule

interface probe_if;
endinterface

module other_probe;
endmodule

module owner;
  leaf u_leaf ();
  bind owner.u_leaf probe_if u_probe ();
endmodule

module t;
  leaf u_leaf1 ();
  leaf u_leaf2 ();
  owner u_owner ();
endmodule

bind t.u_leaf2 probe_if u_probe ();
bind t.u_leaf1 probe_if u_probe ();
bind t.u_leaf1 probe_if u_probe ();  // Bad: duplicate in the same instance
bind t.u_owner.u_leaf other_probe u_probe ();  // Bad: duplicate of the bind in owner
