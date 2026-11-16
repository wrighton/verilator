// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// References to an interface port of an interface, through an interface port or hierarchically

interface inner #(
    parameter int W = 4
);
  logic [W-1:0] x;
  modport mp(input x);
endinterface

interface mid #(
    parameter int W = 4
) (
    inner p
);
endinterface

interface outer #(
    parameter int W = 4
) (
    inner p,
    inner.mp pm,
    mid m
);
  virtual inner #(W) vref;
  virtual inner #(W).mp vrefm;
endinterface

module leaf (
    inner i,
    output logic [6:0] q
);
  assign q = i.x;
endmodule

// Its own port through its own instance name
module leaf_self (
    inner i
);
  virtual inner #(7) v;
  initial v = ls.i;
endmodule

module sub_access (
    outer o,
    output logic [6:0] q
);
  virtual inner #(7) vm;
  leaf l (
      .i(o.p),
      .q(q)
  );
  initial begin
    o.vref = o.p;
    o.vrefm = o.pm;
    vm = o.m.p;
  end
endmodule

module t (
    input clk
);
  int cyc = 0;

  inner #(7) in ();
  mid #(7) md (in);
  outer #(7) ou (
      in,
      in,
      md
  );
  logic [6:0] q;
  sub_access u (
      .o(ou),
      .q(q)
  );

  virtual inner #(7) vt;
  virtual inner #(7) vu;
  virtual inner #(7) vm;
  initial begin
    vt = ou.p;
    vu = u.o.p;
    vm = ou.m.p;
  end

  // Through an element of an instance array
  outer #(7) ous[2] (
      in,
      in,
      md
  );
  virtual inner #(7) va;
  initial va = ous[1].p;

  // Through a generate block, and with a generate loop index
  for (genvar g = 0; g < 2; ++g) begin : gen
    outer #(7) og (
        in,
        in,
        md
    );
    virtual inner #(7) vi;
    initial vi = ous[g].p;
  end
  virtual inner #(7) vg;
  initial vg = gen[0].og.p;

  leaf_self ls (.i(in));

  always @(posedge clk) begin
    cyc <= cyc + 1;
    in.x <= 7'(cyc * 5 + 3);
    if (cyc > 1) begin
      `checkh(q, in.x);
      `checkh(ou.vref.x, in.x);
      `checkh(ou.vrefm.x, in.x);
      `checkh(u.vm.x, in.x);
      `checkh(vt.x, in.x);
      `checkh(vu.x, in.x);
      `checkh(vm.x, in.x);
      `checkh(va.x, in.x);
      `checkh(ous[1].p.x, in.x);
      `checkh(gen[0].vi.x, in.x);
      `checkh(gen[1].vi.x, in.x);
      `checkh(vg.x, in.x);
      `checkh(ls.v.x, in.x);
    end
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
