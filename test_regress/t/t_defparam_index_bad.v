// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  sub #(.N(2)) u_sub2 ();
  sub #(.N(3)) u_sub3 ();
  sub #(.N(0)) u_sub0 ();
  other u_other ();
  defparam u_sub2.gen[4].u_leaf.P = 1;  // Bad: no such iteration
endmodule

module sub #(
    parameter int N = 1
);
  for (genvar i = 0; i < N; ++i) begin : gen
    leaf u_leaf ();
  end
  leaf u_leaf ();  // Not named by the path, as its iteration is not built
  defparam gen[2].u_leaf.P = 1;  // Bad: no such iteration in u_sub2
endmodule

module leaf;
  parameter P = 0;
endmodule

module other;
  defparam t.u_sub3.gen[3].u_leaf.P = 1;  // Bad: no such iteration
  defparam t.u_sub0.gen[0].u_leaf.P = 1;  // Bad: no iterations
endmodule
