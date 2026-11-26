// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A task or function of a hierarchical block is not a port, so not accessible

// A block inside a block, whose path the scope check reports once
module nested (
    input logic [7:0] i,
    output logic [7:0] o
);
  /*verilator hier_block*/
  function automatic logic [7:0] nf(input logic [7:0] v);
    return v + 8'd2;
  endfunction
  assign o = i;
endmodule

// An upward reference by the block's name, from a module inside it
module sub (
    input logic [7:0] i,
    output logic [7:0] o
);
  assign o = leaf.add1(i);
endmodule

module leaf (
    input logic [7:0] i,
    output logic [7:0] o
);
  /*verilator hier_block*/
  function automatic logic [7:0] add1(input logic [7:0] v);
    return v + 8'd1;
  endfunction
  task automatic show();
    $display("%x", i);
  endtask
  // Its own path to itself, and one from a module inside it, are not from outside
  logic [7:0] self, subo;
  assign self = leaf.add1(i);
  sub u_sub (
      .i(i),
      .o(subo)
  );
  logic [7:0] nestedo;
  nested u_nested (
      .i(i),
      .o(nestedo)
  );
  assign o = i + self - i + subo - subo + nestedo - nestedo;
endmodule

module t (
    input logic [7:0] in,
    output logic [7:0] out
);
  logic [7:0] w;
  leaf u_leaf (
      .i(in),
      .o(w)
  );
  assign out = u_leaf.add1(w);
  initial u_leaf.show();
  // Reported once, by the scope check
  logic [7:0] two;
  assign two = u_leaf.u_nested.nf(w);
endmodule
