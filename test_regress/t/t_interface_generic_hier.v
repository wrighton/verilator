// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Generic interface ports connected to hierarchical references to interface instances

interface ch_if;
  logic [6:0] d;
endinterface

interface bus_if;
  ch_if req ();
  ch_if rsp ();
endinterface

interface top_if;
  bus_if b ();
endinterface

module holder;
  ch_if loc ();
endmodule

module drv (
    interface a,
    interface b,
    interface c,
    input logic [6:0] v
);
  assign a.d = v;
  assign b.d = v + 7'd1;
  assign c.d = v + 7'd2;
endmodule

module mon (
    interface g,
    output logic [6:0] q
);
  assign q = g.d;
endmodule

module t;
  logic [6:0] v = 7'h15;
  logic [6:0] q;

  bus_if b ();
  top_if tp ();
  holder h ();

  drv u_drv (
      .a(b.req),
      .b(tp.b.rsp),
      .c(h.loc),
      .v(v)
  );
  mon u_mon (
      .g(b.req),
      .q(q)
  );

  initial begin
    #1;
    `checkh(b.req.d, 7'h15);
    `checkh(tp.b.rsp.d, 7'h16);
    `checkh(h.loc.d, 7'h17);
    `checkh(q, 7'h15);
    v = 7'h7f;
    #1;
    `checkh(b.req.d, 7'h7f);
    `checkh(tp.b.rsp.d, 7'h00);
    `checkh(h.loc.d, 7'h01);
    `checkh(q, 7'h7f);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
