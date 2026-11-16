// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A defparam path may select an element of a generate loop (IEEE 1800-2023 23.10.1)

module leaf (
    input int in,
    output int out
);
  parameter int P = 1;
  initial begin : blk
    parameter Q = 0;
  end
  assign out = in * P + blk.Q * 1000;
endmodule

interface ifc;
  parameter int W = 1;
  logic [W-1:0] d;
endinterface

module mid (
    input int in,
    output int out[2],
    output int nested[3][2]
);
  if (1) begin : g_rtl
    for (genvar i = 0; i < 2; ++i) begin : grid
      leaf u_leaf (
          .in(in),
          .out(out[i])
      );
    end
  end
  for (genvar i = 2; i < 5; ++i) begin : outer
    for (genvar j = 0; j < 2; ++j) begin : inner
      leaf u_leaf (
          .in(in),
          .out(nested[i-2][j])
      );
    end
  end
  // Path starting with a selected block, from inside the module
  defparam outer[2].inner[1].u_leaf.P = 21;
endmodule

module t;
  // Interface instance in a generate block
  if (1) begin : g_ifc
    ifc bus ();
  end
  defparam g_ifc.bus.W = 8;
  assign g_ifc.bus.d = '1;
  // Interface parameter used before the interface instance
  logic [abus.W-1:0] early = '1;
  ifc abus ();
  defparam abus.W = 6;

  int in;
  int out_a[2];
  int out_b[2];
  int nested_a[3][2];
  int nested_b[3][2];
  mid u_a (
      .in(in),
      .out(out_a),
      .nested(nested_a)
  );
  mid u_b (
      .in(in),
      .out(out_b),
      .nested(nested_b)
  );
  // Same name as the end of a defparam path, but not under it
  int out_c;
  leaf u_leaf (
      .in(in),
      .out(out_c)
  );
  defparam u_a.g_rtl.grid[1].u_leaf.P = 3;
  defparam u_b.g_rtl.grid[0].u_leaf.P = 5;
  defparam u_b.outer[4].inner[0].u_leaf.P = 7;
  defparam u_b.outer[3].inner[1].u_leaf.blk.Q = 2;

  initial begin
    for (in = 1; in < 4; ++in) begin
      #1;
      `checkd(out_a[0], in);
      `checkd(out_a[1], in * 3);
      `checkd(out_b[0], in * 5);
      `checkd(out_b[1], in);
      `checkd(nested_a[0][1], in * 21);
      `checkd(nested_a[2][0], in);
      `checkd(nested_b[0][1], in * 21);
      `checkd(nested_b[1][1], in + 2000);
      `checkd(nested_b[2][0], in * 7);
      `checkd(nested_b[2][1], in);
      `checkd(out_c, in);
      `checkd(int'(g_ifc.bus.d), 255);
      `checkd(int'(early), 63);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
