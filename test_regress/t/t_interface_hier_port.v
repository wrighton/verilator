// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Hierarchical references to interface instances and their modports
// See also t_interface_hier_port_bad.v

interface ifc;
  logic [6:0] d;
  modport mp(output d);
  modport mc(input d);
endinterface

module prod (
    ifc.mp b,
    input logic [6:0] v
);
  assign b.d = v;
endmodule

module cons (
    ifc.mc b,
    output logic [6:0] q
);
  assign q = b.d;
endmodule

interface bus;
  ifc arr[3:2] ();
  ifc grid[2][3:1] ();
endinterface

// Modports of elements of an interface array nested in an interface port
module bprod (
    bus bp,
    input logic [6:0] v
);
  prod p0 (
      .b(bp.arr[2].mp),
      .v(v)
  );
  prod p1 (
      .b(bp.grid[0][1].mp),
      .v(~v)
  );
endmodule

module sub #(
    parameter logic [6:0] P = 0
) (
    input logic [6:0] x
);
  ifc loc ();
  prod p (
      .b(loc.mp),
      .v(x ^ P)
  );
endmodule

module t;
  logic [6:0] x = 7'h15;

  sub #(7'h11) u1 (.x(x));
  sub #(7'h22) u2 (.x(x));

  for (genvar g = 0; g < 2; ++g) begin : gfor
    ifc loc ();
    prod p (
        .b(loc.mp),
        .v(x + 7'(g))
    );
  end

  // Interface port actuals that are hierarchical references to a modport
  logic [6:0] q1, q2, q3;
  cons c1 (
      .b(u1.loc.mc),
      .q(q1)
  );
  cons c2 (
      .b(u2.loc.mc),
      .q(q2)
  );
  cons c3 (
      .b(u2.loc),
      .q(q3)
  );

  // Modports of elements of interface arrays, nested and multidimensional
  bus b1 ();
  bus b2 ();
  ifc la[1:0][2:4] ();
  logic [6:0] q4, q5;
  prod p4 (
      .b(b1.arr[3].mp),
      .v(x + 7'h1)
  );
  prod p5 (
      .b(b1.grid[1][2].mp),
      .v(x + 7'h2)
  );
  prod p6 (
      .b(la[0][3].mp),
      .v(x + 7'h3)
  );
  bprod p7 (
      .bp(b2),
      .v(x)
  );
  cons c4 (
      .b(b1.arr[3].mc),
      .q(q4)
  );
  cons c5 (
      .b(b2.grid[0][1].mc),
      .q(q5)
  );

  initial begin
    virtual ifc.mc vmc;
    virtual ifc vif;
    #1;
    `checkh(q1, 7'h04);
    `checkh(q2, 7'h37);
    `checkh(q3, 7'h37);
    `checkh(q4, 7'h16);
    `checkh(q5, 7'h6a);
    `checkh(b1.grid[1][2].d, 7'h17);
    `checkh(la[0][3].d, 7'h18);
    `checkh(b2.arr[2].d, 7'h15);
    x = 7'h4a;
    #1;
    `checkh(q1, 7'h5b);
    `checkh(q2, 7'h68);
    `checkh(q3, 7'h68);
    `checkh(q4, 7'h4b);
    `checkh(q5, 7'h35);
    `checkh(b1.grid[1][2].d, 7'h4c);
    `checkh(la[0][3].d, 7'h4d);
    `checkh(b2.arr[2].d, 7'h4a);
    // Virtual interfaces from hierarchical references, also through a generate block
    vmc = u1.loc.mc;
    `checkh(vmc.d, 7'h5b);
    vmc = gfor[1].loc.mc;
    `checkh(vmc.d, 7'h4b);
    vmc = b1.grid[1][2].mc;
    `checkh(vmc.d, 7'h4c);
    vif = gfor[0].loc;
    `checkh(vif.d, 7'h4a);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
