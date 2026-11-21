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
  leaf u_leaf ();
endmodule

module loop;
  for (genvar g = 0; g < 2; ++g) begin : gen
    leaf u_leaf ();
  end
  bind gen[0].u_leaf sub u_mon2 ();
endmodule

module t #(
    parameter bit FIRST = 1
);
  sub u_sub ();
  loop u_loop ();
  leaf u_arr[1:0] ();
  for (genvar g = 0; g < 2; ++g) begin : gen
    leaf u_leaf ();
  end
  if (1) begin
    leaf u_leaf ();
  end
  if (1) begin
    begin : g_inner
      leaf u_leaf ();
    end
  end
  generate
    begin
      logic unused;
      leaf u_in_decl ();
    end
  endgenerate
  if (FIRST) begin : g_alt
    leaf u_leaf ();
  end else begin : g_alt
    leaf u_leaf ();
  end

  localparam int IDX = 1;
  bind gen[IDX].u_leaf probe_if u_probe ();
  bind gen[0][0].u_leaf probe_if u_probe ();
  bind u_arr[0] probe_if u_probe ();
  bind genblk2.u_leaf probe_if u_probe ();
  bind g_inner.u_leaf probe_if u_probe ();
  bind g_alt.u_leaf probe_if u_probe ();
  bind t.u_in_decl probe_if u_probe ();
  bind gen[0].u_leaf sub u_mon ();
  bind gen[1].u_leaf leaf u_mon ();
  if (1) begin : g_bind
    bind t.gen[0].u_leaf probe_if u_probe ();
  end
endmodule

bind sub.u_leaf probe_if u_probe ();
bind t.u_loop.gen[1].u_leaf leaf u_mon2 ();
