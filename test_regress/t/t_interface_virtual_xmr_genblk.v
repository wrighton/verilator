// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface pif;
  int id;
endinterface

interface ppif #(
    parameter int W = 1
);
  logic [W-1:0] data;
endinterface

module w;
endmodule

module h;
  for (genvar i = 0; i < 2; i++) begin : g_i
    pif u ();
    initial u.id = 10 + i;
    for (genvar j = 0; j < 3; j++) begin : g_j
      pif u ();
      initial u.id = 100 + 10 * i + j;
    end
    ppif #(.W(8)) p ();
    assign p.data = 8'(200 + i);
  end
  if (1) begin : g_if
    pif u ();
    initial u.id = 20;
  end
endmodule

bind w h u_h ();

class Cls;
  virtual pif vif;
  virtual ppif #(8) pvif;
endclass

module t;
  w u_w ();

  virtual pif mvif;

  for (genvar k = 0; k < 2; k++) begin : g_t
    pif u ();
    initial u.id = 40 + k;
  end

  class Inner;
    virtual pif vif;
    function void set();
      vif = u_w.u_h.g_i[1].g_j[0].u;
    endfunction
  endclass

  initial begin
    automatic Cls c = new;
    automatic Inner n = new;
    #1;
    c.vif = u_w.u_h.g_i[0].u;
    `checkd(c.vif.id, 10);
    c.vif = u_w.u_h.g_i[1].u;
    `checkd(c.vif.id, 11);
    c.vif = u_w.u_h.g_i[1].g_j[2].u;
    `checkd(c.vif.id, 112);
    c.vif = u_w.u_h.g_if.u;
    `checkd(c.vif.id, 20);
    c.pvif = u_w.u_h.g_i[1].p;
    `checkd(c.pvif.data, 201);
    mvif = u_w.u_h.g_i[0].g_j[1].u;
    `checkd(mvif.id, 101);
    mvif = g_t[1].u;
    `checkd(mvif.id, 41);
    n.set();
    `checkd(n.vif.id, 110);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
