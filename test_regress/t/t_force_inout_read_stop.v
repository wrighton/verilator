// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0)
// verilog_format: on

// What stops the bits of an inout port reaching a forced port, which then keeps its force domain,
// and what does not. Each case has modules of its own, as a port is fed from an inout port only
// if every instance is, and checks whether a force of the port reaches its connection.

// A forced variable carries its forced value
module f_leaf (
    input wire p
);
endmodule
module f_relay (
    input wire i
);
  wire w = i;
  f_leaf leaf (w);
endmodule
module f_mid (
    inout wire io
);
  wire a = io;
  f_relay relay (a);
endmodule

// A strength assignment may drop the inout port's value
module s_leaf (
    input wire p
);
endmodule
module s_relay (
    input wire i
);
  wire w = i;
  s_leaf leaf (w);
endmodule
module s_mid (
    inout wire io
);
  wire a;
  assign (strong0, highz1) a = io;
  s_relay relay (a);
endmodule

// A forced input port carries its forced value, though it is fed from the inout port itself
module i_leaf (
    input wire p
);
endmodule
module i_relay (
    input wire i
);
  wire w = i;
  i_leaf leaf (w);
endmodule
module i_mid (
    inout wire io
);
  wire a = io;
  i_relay relay (a);
endmodule

// An inout connection driving the variable keeps it from an input port
module w_leaf (
    input wire p
);
endmodule
module w_drive (
    inout wire o,
    input bit v
);
  assign o = v;
endmodule
module w_mid (
    inout wire io,
    input bit v
);
  wire a = io;
  w_drive drive (
      a,
      v
  );
  w_leaf leaf (a);
endmodule

// And from another inout connection
module m_leaf (
    inout wire p
);
endmodule
module m_drive (
    inout wire o,
    input bit v
);
  assign o = v;
endmodule
module m_mid (
    inout wire io,
    input bit v
);
  logic q;
  assign q = io;
  wire a = q;
  m_drive drive (
      a,
      v
  );
  m_leaf leaf (a);
endmodule

// But not from the bits it does not drive
module d_drive (
    inout wire p
);
  assign p = 1'b1;
endmodule
module d_leaf (
    input wire p
);
endmodule
module d_mid (
    inout wire io
);
  wire [1:0] a;
  assign a = {2{io}};
  d_drive drive (a[1]);
  wire b = a[0];
  d_leaf leaf (b);
endmodule

// A conditional both of whose arms carry does not carry a forced input port's bits
module c_leaf (
    inout wire p
);
endmodule
module c_relay (
    input wire bad,
    inout wire io,
    input bit pick
);
  logic q;
  assign q = io;
  // Longer than the path to bad, so that bad carries before g
  wire g1 = q;
  wire g2 = g1;
  wire g = g2;
  wire b = pick ? bad : g;
  c_leaf leaf (b);
endmodule
module c_mid (
    inout wire io,
    input bit pick
);
  logic q;
  assign q = io;
  wire a = q;
  c_relay relay (
      a,
      io,
      pick
  );
endmodule

// Nor those of a variable an inout connection drives
module k_leaf (
    inout wire p
);
endmodule
module k_drive (
    inout wire o,
    input bit v
);
  assign o = v;
endmodule
module k_mid (
    inout wire io,
    input bit pick
);
  logic q;
  assign q = io;
  wire a = q;
  k_drive drive (
      a,
      1'b1
  );
  wire g = io;
  wire b = pick ? a : g;
  k_leaf leaf (b);
endmodule

// A writable public variable may be written otherwise
module p_leaf (
    input wire p
);
endmodule
module p_mid (
    inout wire io
);
  wire a  /*verilator public_flat_rw*/;
  assign a = io;
  wire b = a;
  p_leaf leaf (b);
endmodule

// Nor that of a read-only public variable
module u_leaf (
    input wire p
);
endmodule
module u_mid (
    inout wire io
);
  wire a  /*verilator public_flat_rd*/;
  assign a = io;
  wire b = a;
  u_leaf leaf (b);
endmodule

// A driver of an inout connection two instances down drives it
module x_leaf (
    input wire p
);
endmodule
module x_deep (
    inout wire y
);
  assign y = 1'b1;
endmodule
module x_sub (
    inout wire x
);
  x_deep deep (x);
endmodule
module x_mid (
    inout wire io
);
  wire a = io;
  x_sub sub (a);
  wire b = a;
  x_leaf leaf (b);
endmodule

// A concatenated connection drives only its bits
module g_leaf (
    input wire p
);
endmodule
module g_drive (
    inout wire [1:0] o
);
  assign o = 2'b11;
endmodule
module g_mid (
    inout wire io
);
  wire [2:0] a;
  assign a = {3{io}};
  g_drive drive ({a[2], a[0]});
  wire b = a[1];
  g_leaf leaf (b);
endmodule

// An inout port driven only by a force drives its connection
module o_sibling (
    inout wire p
);
  task automatic on;
    force p = 1'b1;
  endtask
endmodule
module o_leaf (
    inout wire p
);
endmodule
module o_mid (
    inout wire io
);
  logic q;
  assign q = io;
  wire a = q;
  o_sibling sibling (a);
  wire b = a;
  o_leaf leaf (b);
endmodule

// So does one forced through a hierarchical reference
module q_sibling (
    inout wire p
);
endmodule
module q_leaf (
    inout wire p
);
endmodule
module q_mid (
    inout wire io
);
  logic q;
  assign q = io;
  wire a = q;
  q_sibling sibling (a);
  wire b = a;
  q_leaf leaf (b);
endmodule

// A force in its module forces every instance, so each drives the connection of the others
module l_twin (
    inout wire p
);
  task automatic on;
    force p = 1'b1;
  endtask
endmodule
module l_mid (
    inout wire io
);
  logic q;
  assign q = io;
  wire a = q;
  l_twin t1 (a);
  l_twin t2 (a);
endmodule

// So does one forced in its module through a concatenation target
module z_twin (
    inout wire x,
    input bit go
);
  wire y;
  always @(posedge go) force {x, y} = 2'b00;
endmodule
module z_mid (
    inout wire io,
    input bit go
);
  logic q;
  assign q = io;
  wire a = q;
  z_twin t1 (
      a,
      go
  );
  z_twin t2 (
      a,
      1'b0
  );
endmodule

// And one forced through a hierarchical reference, on the connection itself
module r_sibling (
    inout wire p
);
endmodule
module r_leaf (
    inout wire p
);
endmodule
module r_mid (
    inout wire io
);
  logic q;
  assign q = io;
  wire a = q;
  r_sibling sibling (a);
  r_leaf leaf (a);
endmodule

// Or two instances down
module v_inner (
    inout wire p
);
endmodule
module v_outer (
    inout wire q
);
  v_inner inner (q);
endmodule
module v_leaf (
    inout wire p
);
endmodule
module v_mid (
    inout wire io
);
  logic q;
  assign q = io;
  wire a = q;
  v_outer outer (a);
  v_leaf leaf (a);
endmodule

// A port driving its own connection beside another driver
module y_leaf (
    inout wire p
);
  assign p = 1'b1;
endmodule
module y_drive (
    inout wire p
);
  assign p = 1'b1;
endmodule
module y_mid (
    inout wire io
);
  logic q;
  assign q = io;
  wire a = q;
  y_drive drive (a);
  y_leaf leaf (a);
endmodule

// A pull on a concatenated connection pulls its bits
module h_pulled (
    inout wire [1:0] x
);
  pullup (x[0]);
  pullup (x[1]);
endmodule
module h_leaf (
    input wire p
);
endmodule
module h_mid (
    inout wire io
);
  wire [2:0] a;
  assign a = {3{io}};
  h_pulled pulled ({a[2], a[1]});
  wire b = a[1];
  h_leaf leaf (b);
endmodule

module t;
  bit en = 1, v = 1, pick = 1;
  wire n = en ? v : 1'bz;
  f_mid fm (n);
  s_mid sm (n);
  i_mid im (n);
  w_mid wm (
      n,
      v
  );
  m_mid mm (
      n,
      1'b1
  );
  d_mid dm (n);
  c_mid cm (
      n,
      pick
  );
  k_mid km (
      n,
      pick
  );
  p_mid pm (n);
  u_mid um (n);
  x_mid xm (n);
  g_mid gm (n);
  o_mid om (n);
  q_mid qm (n);
  l_mid lm (n);
  bit z_go = 0;
  z_mid zm (
      n,
      z_go
  );
  r_mid rm (n);
  v_mid vm (n);
  y_mid ym (n);
  h_mid hm (n);
  // Never called: make the ports of r_sibling and v_inner forced
  task automatic force_siblings;
    force rm.sibling.p = 1'b1;
    force vm.outer.inner.p = 1'b1;
  endtask
  // Never called: makes the port of q_sibling forced
  task automatic force_q_sibling;
    force qm.sibling.p = 1'b1;
  endtask
  initial begin
    force fm.a = 1'b0;
    force im.relay.i = 1'b0;
    force cm.relay.bad = 1'b1;
    #1;
    `checkh({fm.relay.w, im.relay.w, sm.relay.w}, 3'b000);
    `checkh({wm.a, mm.a, dm.b, cm.relay.b, km.b, pm.b, um.b, xm.b, gm.b, om.b, qm.b, lm.a, zm.a, rm.a, vm.a, ym.a, hm.b}, 17'h1ffff);
    // A force of a port on a force domain reaches its connection; of one fed from the inout port,
    // which keeps its own net, it does not
    force fm.relay.leaf.p = 1'b1;
    force im.relay.leaf.p = 1'b1;
    force sm.relay.leaf.p = 1'b1;
    force wm.leaf.p = 1'b0;
    force mm.leaf.p = 1'b0;
    force dm.leaf.p = 1'b0;
    force cm.relay.leaf.p = 1'b0;
    force km.leaf.p = 1'b0;
    force pm.leaf.p = 1'b0;
    force um.leaf.p = 1'b0;
    force xm.leaf.p = 1'b0;
    force gm.leaf.p = 1'b0;
    force om.leaf.p = 1'b0;
    force qm.leaf.p = 1'b0;
    force lm.t1.p = 1'b0;
    z_go = 1;
    force rm.leaf.p = 1'b0;
    force vm.leaf.p = 1'b0;
    force ym.leaf.p = 1'b0;
    force hm.leaf.p = 1'b0;
    #1;
    // Force domains
    `checkh({fm.relay.w, im.relay.w, sm.relay.w}, 3'b111);
    `checkh({wm.a, mm.a, cm.relay.b, km.b, pm.b, xm.b, om.b, qm.b, lm.a, zm.a, rm.a, vm.a, ym.a, hm.b}, 14'h0000);
    // Fed from the inout port
    `checkh({dm.leaf.p, um.leaf.p, gm.leaf.p}, 3'b000);
    `checkh({dm.b, um.b, gm.b}, 3'b111);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
