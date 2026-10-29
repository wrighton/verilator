// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Nested interface instances used as port actuals through an interface port
// that is itself connected to another interface port

interface ch_if;
  logic [6:0] d;
endinterface

interface bus_if;
  ch_if o0 ();
  ch_if o1 ();
  ch_if arr[2] ();
endinterface

interface top_if;
  bus_if bb ();
  bus_if ba[2:1] ();
endinterface

module chdrv (
    ch_if g,
    input logic [6:0] v
);
  assign g.d = v;
endmodule

module busdrv (
    bus_if bp,
    input logic [6:0] v
);
  chdrv u0 (
      .g(bp.o0),
      .v(v)
  );
  chdrv u1 (
      .g(bp.o1),
      .v(v + 7'h1)
  );
  assign bp.arr[1].d = v + 7'h2;
endmodule

// Two and three levels of interface ports above busdrv
module passdrv (
    bus_if bq,
    input logic [6:0] v
);
  busdrv b (
      .bp(bq),
      .v(v)
  );
endmodule

module arrdrv (
    bus_if bs[2:1],
    input logic [6:0] v
);
  busdrv b1 (
      .bp(bs[1]),
      .v(v + 7'h10)
  );
  passdrv b2 (
      .bq(bs[2]),
      .v(v + 7'h20)
  );
endmodule

module topdrv (
    top_if tp,
    input logic [6:0] v
);
  passdrv p (
      .bq(tp.bb),
      .v(v)
  );
  arrdrv a (
      .bs(tp.ba),
      .v(v)
  );
endmodule

module t;
  logic clk = 0;
  int cyc = 0;
  logic [6:0] v;

  top_if tt ();
  topdrv d (
      .tp(tt),
      .v(v)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    v <= 7'(cyc * 3);
    if (cyc > 1) begin
      `checkh(tt.bb.o0.d, v);
      `checkh(tt.bb.o1.d, v + 7'h1);
      `checkh(tt.bb.arr[1].d, v + 7'h2);
      `checkh(tt.ba[1].o0.d, v + 7'h10);
      `checkh(tt.ba[1].o1.d, v + 7'h11);
      `checkh(tt.ba[1].arr[1].d, v + 7'h12);
      `checkh(tt.ba[2].o0.d, v + 7'h20);
      `checkh(tt.ba[2].o1.d, v + 7'h21);
      `checkh(tt.ba[2].arr[1].d, v + 7'h22);
    end
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
