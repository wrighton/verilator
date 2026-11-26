// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Paths from inside a hierarchical block through one of its own instances,
// starting at the block by its module name (IEEE 1800-2023 23.8), which the
// block's own run resolves
module inner (
    input logic [7:0] i,
    output logic [7:0] o
);
  assign o = leaf.u_sibling.sf(i) ^ leaf.u_sibling.k;
endmodule

module inner_b (
    input logic [7:0] i,
    output logic [7:0] o
);
  assign o = leafb.u_sibling.sf(i);  // The innermost block, in another
endmodule

module sibling (
    input logic [7:0] i,
    output logic [7:0] o
);
  localparam logic [7:0] k = 8'h30;
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
  logic [7:0] w1, w2;
  sibling u_sibling (
      .i(i),
      .o(w1)
  );
  inner_b u_inner_b (
      .i(i),
      .o(w2)
  );
  assign o = w1 ^ w2;
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
  initial begin
    for (int v = 0; v < 256; v += 37) begin
      in = v[7:0];
      #1;
      `checkh(out, in ^ ((in + 8'd2) ^ 8'h30) ^ (in ^ (in + 8'd2)));
      `checkh(out2, out);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
