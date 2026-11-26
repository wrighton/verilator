// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Paths from inside a hierarchical block into it that its own run cannot
// resolve, as they do not start at the innermost block by its module name

module inner (
    input logic [7:0] i,
    output logic [7:0] o
);
  // Leaves the block, to come back into it through its instance
  assign o = t.u_leaf.u_sibling.sf(i)
      // By the name of its instance
      ^ u_leaf.u_sibling.sf(i)
      // Into another instance of the block
      ^ u_leaf2.u_sibling.sf(i);
endmodule

module inner_b (
    input logic [7:0] i,
    output logic [7:0] o
);
  assign o = leaf.u_sibling.sf(i);  // Leaves the innermost block
endmodule

module sibling (
    input logic [7:0] i,
    output logic [7:0] o
);
  function automatic logic [7:0] sf(input logic [7:0] v);
    return v + 8'd2;
  endfunction
  assign o = i;
endmodule

module leafb (
    input logic [7:0] i,
    output logic [7:0] o
);
  /*verilator hier_block*/
  inner_b u_inner_b (
      .i(i),
      .o(o)
  );
endmodule

module leaf (
    input logic [7:0] i,
    output logic [7:0] o
);
  /*verilator hier_block*/
  logic [7:0] w1, w2, w3;
  sibling u_sibling (
      .i(i),
      .o(w1)
  );
  inner u_inner (
      .i(i),
      .o(w2)
  );
  leafb u_leafb (
      .i(i),
      .o(w3)
  );
  assign o = w1 ^ w2 ^ w3;
endmodule

module t;
  logic [7:0] in;
  logic [7:0] out, out2;
  leaf u_leaf (
      .i(in),
      .o(out)
  );
  leaf u_leaf2 (
      .i(in),
      .o(out2)
  );
endmodule
