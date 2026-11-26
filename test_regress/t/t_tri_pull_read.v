// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module leaf (
    input tri1 a,
    output logic isz,
    output logic val,
    output logic bval
);
  tri1 b;
  assign b = a;
  assign isz = (a === 1'bz);
  assign val = a;
  assign bval = b;
endmodule

// An input port pulled on one bit reads the other bits as its connection drives them
module leaf4 (
    input wire [3:0] pb,
    output logic [3:0] zs
);
  pullup (pb[2]);
  for (genvar i = 0; i < 4; ++i) begin : g
    assign zs[i] = (pb[i] === 1'bz);
  end
endmodule

// Passing an input through to it, once or twice
module mid4 (
    input wire [3:0] mi,
    output logic [3:0] zs
);
  leaf4 u (
      .pb(mi),
      .zs
  );
endmodule

module mid4b (
    input wire [3:0] mbi,
    output logic [3:0] zs
);
  mid4 u (
      .mi(mbi),
      .zs
  );
endmodule

// Through a relay, or connected to a part of a tristate net
module leaf1 (
    input wire [3:0] p,
    output wire z
);
  pullup (p[2]);
  assign z = (p[0] === 1'bz);
endmodule

module relay1 (
    input wire [3:0] p,
    output wire z
);
  leaf1 l (
      .p,
      .z
  );
endmodule

module t;
  localparam realtime STEP = 1ns;
  // Pulled nets with a driver, or without one, never read as z
  logic d;
  logic isz;
  logic val;
  logic bval;
  leaf u (
      .a(d),
      .isz,
      .val,
      .bval
  );
  logic [3:0] zs4;
  logic [3:0] zs4z;
  logic [3:0] zs4n;
  wire [3:0] w4;
  assign w4 = {d, d, d, 1'bz};
  leaf4 u4 (
      .pb({d, d, d, d}),
      .zs(zs4)
  );
  leaf4 u4z (
      .pb(w4),
      .zs(zs4z)
  );
  logic [3:0] zs4m;
  logic [3:0] zs4mm;
  logic [3:0] zs4mc;
  mid4 u4m (
      .mi(w4),
      .zs(zs4m)
  );
  mid4b u4mm (
      .mbi(w4),
      .zs(zs4mm)
  );
  mid4 u4mc (
      .mi(4'bz00z),
      .zs(zs4mc)
  );
  wire [3:0] dr = d ? 4'h0 : 4'hz;
  wire [7:0] dr8 = d ? 8'h50 : 8'hzz;
  wire zr;
  wire zsel;
  relay1 ur (
      .p(dr),
      .z(zr)
  );
  leaf1 usel (
      .p(dr8[3:0]),
      .z(zsel)
  );
  leaf4 u4n (
      .pb(),
      .zs(zs4n)
  );
  tri0 n0;
  tri1 n1;
  tri hb;
  assign hb = u.b;
  initial begin
    for (int i = 0; i < 4; ++i) begin
      d = i[0];
      #STEP;
      `checkh(isz, 1'b0);
      `checkh(val, d);
      `checkh(bval, d);
      `checkh(u.b === 1'bz, 1'b0);
      `checkh(hb, d);
      `checkh(n0 === 1'bz, 1'b0);
      `checkh(n1 === 1'bz, 1'b0);
      `checkh(zs4, 4'b0000);
      `checkh(zs4z, 4'b0001);
      `checkh(zs4n, 4'b1011);
      `checkh(zs4m, 4'b0001);
      `checkh(zs4mm, 4'b0001);
      `checkh(zs4mc, 4'b1001);
      `checkh(zr, ~d);
      `checkh(zsel, ~d);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
