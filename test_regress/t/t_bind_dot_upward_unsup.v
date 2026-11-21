// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf;
endmodule

module other;
endmodule

interface probe_if;
endinterface

module sub;
  leaf u_leaf ();
endmodule

module other_sub;
  other u_leaf ();
endmodule

module named_t;
  other_sub u_sub ();
endmodule

module owner;
  // From the instance of owner, t is found upwards as the instance of named_t
  bind t.u_sub.u_leaf probe_if u_probe ();
endmodule

module wrap;
  named_t t ();
  owner o ();
endmodule

module same_t;
  sub u_sub ();
endmodule

module same_owner;
  // From the instance of same_owner, t is found upwards as the instance of same_t
  bind t.u_sub.u_leaf probe_if u_probe ();
endmodule

module same_wrap;
  same_t t ();
  same_owner o ();
endmodule

module top_owner;
  // From the top module, as no instance named t is found upwards
  bind t.u_sub.u_leaf probe_if u_top_probe ();
endmodule

module t;
  sub u_sub ();
  wrap u_wrap ();
  same_wrap u_same ();
  top_owner u_top_owner ();
endmodule
