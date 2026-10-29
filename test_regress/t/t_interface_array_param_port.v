// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Ports that are arrays of a parameterized interface, with the parameters given

interface bus_if #(
    parameter int W = 8
);
  logic [W-1:0] d;
endinterface

interface top_if #(
    parameter int W = 8
);
  bus_if #(W * 2) bb[2] ();
endinterface

module drv #(
    parameter int W = 8
) (
    bus_if #(W) bp,
    input logic [W-1:0] v
);
  assign bp.d = v;
endmodule

module arrdrv #(
    parameter int W = 8
) (
    bus_if #(W) ba[2:1],
    input logic [W-1:0] v
);
  drv #(W) d1 (
      .bp(ba[1]),
      .v(v)
  );
  drv #(W) d2 (
      .bp(ba[2]),
      .v(~v)
  );
endmodule

// Connected from a nested interface array through an interface port
module topdrv #(
    parameter int W = 8
) (
    top_if #(W) tp,
    input logic [2*W-1:0] v
);
  arrdrv #(W * 2) a (
      .ba(tp.bb),
      .v(v)
  );
endmodule

// A multidimensional array port
module arrdrv2 #(
    parameter int W = 8
) (
    bus_if #(W) ba[2][2],
    input logic [W-1:0] v
);
  assign ba[0][0].d = v;
  assign ba[1][1].d = ~v;
endmodule

// A whole parameterized interface array port passed on to an array port
module mid #(
    parameter int W = 8
) (
    bus_if #(W) ba[2:1],
    input logic [W-1:0] v
);
  arrdrv #(W) a (
      .ba(ba),
      .v(v)
  );
endmodule

module sub #(
    parameter int W = 8
) (
    input logic [W-1:0] v
);
  bus_if #(W) ls[2] ();
  arrdrv #(W) a (
      .ba(ls),
      .v(v)
  );
endmodule

module t;
  logic clk = 0;
  int cyc = 0;
  logic [69:0] v;

  // Default parameters, the module is not specialized
  bus_if l8[2] ();
  arrdrv a8 (
      .ba(l8),
      .v(v[7:0])
  );

  // Specialized for the interface parameters, ascending and wide
  bus_if #(5) l5[2] ();
  arrdrv #(5) a5 (
      .ba(l5),
      .v(v[4:0])
  );
  bus_if #(70) l70[3:4] ();
  arrdrv #(70) a70 (
      .ba(l70),
      .v(v)
  );

  // Plain parameterized interface
  bus_if #(6) single6 ();
  drv #(6) ds6 (
      .bp(single6),
      .v(v[5:0])
  );

  // Whole array port passed on, specialized and default
  bus_if #(5) m5[2:1] ();
  mid #(5) mi5 (
      .ba(m5),
      .v(v[4:0])
  );
  bus_if m8[2:1] ();
  mid mi8 (
      .ba(m8),
      .v(v[7:0])
  );

  // Multidimensional
  bus_if #(5) l2d[2][2] ();
  arrdrv2 #(5) a2d (
      .ba(l2d),
      .v(v[4:0])
  );

  // Element of a parameterized interface array
  bus_if #(6) l6[2] ();
  drv #(6) d6 (
      .bp(l6[1]),
      .v(v[5:0])
  );

  // Nested interface arrays, with default and specialized element parameters
  top_if #(4) t4 ();
  topdrv #(4) p4 (
      .tp(t4),
      .v(v[7:0])
  );
  top_if #(3) t3 ();
  topdrv #(3) p3 (
      .tp(t3),
      .v(v[5:0])
  );

  // Instances under a submodule
  sub #(7) s7 (.v(v[6:0]));
  sub #(8) s8 (.v(v[7:0]));

  always #5 clk = ~clk;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    v <= {35'(cyc * 7), 35'(cyc * 13)};
    if (cyc > 1) begin
      `checkh(l8[0].d, ~v[7:0]);
      `checkh(l8[1].d, v[7:0]);
      `checkh(l5[0].d, ~v[4:0]);
      `checkh(l5[1].d, v[4:0]);
      `checkh(l70[3].d, ~v);
      `checkh(l70[4].d, v);
      `checkh(l6[1].d, v[5:0]);
      `checkh(single6.d, v[5:0]);
      `checkh(l2d[0][0].d, v[4:0]);
      `checkh(l2d[1][1].d, ~v[4:0]);
      `checkh(m5[1].d, v[4:0]);
      `checkh(m5[2].d, ~v[4:0]);
      `checkh(m8[1].d, v[7:0]);
      `checkh(m8[2].d, ~v[7:0]);
      `checkh(t4.bb[0].d, ~v[7:0]);
      `checkh(t4.bb[1].d, v[7:0]);
      `checkh(t3.bb[0].d, ~v[5:0]);
      `checkh(t3.bb[1].d, v[5:0]);
      `checkh(s7.ls[0].d, ~v[6:0]);
      `checkh(s7.ls[1].d, v[6:0]);
      `checkh(s8.ls[0].d, ~v[7:0]);
      `checkh(s8.ls[1].d, v[7:0]);
    end
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
