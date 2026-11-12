// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An input net port driven inside its module is coerced to inout
// (IEEE 1800-2023 23.3.3.1), so the driver reaches the connected net.

// verilator lint_off ASSIGNIN

typedef logic [1:0] pair_t;
typedef struct packed {
  logic hi;
  logic lo;
} packed_pair_t;

interface net_if;
  wire [1:0] x;
endinterface

// Driven by a clocking block output
interface drv_if (
    input logic clk,
    input logic d
);
  clocking cb @(posedge clk);
    output d;
  endclocking
endinterface

// Driven by a clocking block output with a skew
interface skew_if (
    input logic clk,
    input logic d
);
  clocking cb @(posedge clk);
    default output #1;
    output d;
  endclocking
endinterface

// Driven by a continuous assignment, possibly with z
module tri_drv (
    input wire pair_t a,
    input logic en,
    input logic [1:0] v
);
  assign a = en ? v : 2'bzz;
endmodule

// Connected to coerced ports of instances
module wrap (
    input wire [1:0] a,
    input logic en,
    input logic [1:0] v
);
  tri_drv u (.a(a), .en(en), .v(v));
  tri_drv u_off (.a(a), .en(1'b0), .v(v));
endmodule

// Inout connected to a coerced port
module io_wrap (
    inout logic [1:0] a,
    input logic en,
    input logic [1:0] v
);
  tri_drv u (.a(a), .en(en), .v(v));
endmodule

// Driven by an output port connection
module out_drv (
    output wire [1:0] o,
    input logic en,
    input logic [1:0] v
);
  assign o = en ? v : 2'bzz;
endmodule
module out_wrap (
    input wire [1:0] a,
    input logic en,
    input logic [1:0] v
);
  out_drv u (.o(a), .en(en), .v(v));
endmodule

// Output port of default kind, so a net, connected to a coerced port
module out_net_wrap (
    output [1:0] o,
    input logic en,
    input logic [1:0] v
);
  tri_drv u (.a(o), .en(en), .v(v));
endmodule

// The following are not coerced, as one of their connections cannot be inout
module var_drv (
    input wire [1:0] a
);
  assign a = 2'b11;
endmodule
module out_var_drv (
    input wire [1:0] a
);
  assign a = 2'b11;
endmodule
module out_var (
    output logic [1:0] o
);
  out_var_drv u (.a(o));
endmodule
module const_drv (
    // verilator lint_off MULTIDRIVEN
    input wire a,
    // verilator lint_on MULTIDRIVEN
    input logic v,
    output wire o
);
  assign a = v;
  assign o = a;
endmodule
module idx_drv (
    input wire a
);
  assign a = 1'b1;
endmodule
module top_drv (
    input wire a
);
  assign a = 1'b1;
endmodule
module cat_drv (
    input wire [1:0] a
);
  assign a = 2'b11;
endmodule
module cat2_drv (
    input wire [1:0] a
);
  assign a = 2'b11;
endmodule
module rep_drv (
    input wire [1:0] a
);
  assign a = 2'b11;
endmodule
module pattern_drv (
    input wire packed_pair_t a
);
  assign a = 2'b11;
endmodule
module cast_drv (
    input wire [1:0] a
);
  assign a = 2'b11;
endmodule

// Not coerced, so the parent port it connects to is not either, unless
// driven inside its module too
module const_child (
    input wire a
);
  assign a = 1'b1;
endmodule
module drv_child (
    input wire a,
    input logic en
);
  assign a = en ? 1'b0 : 1'bz;
endmodule
module child_par (
    input wire a,
    input logic en
);
  const_child u (.a(a));
  drv_child u2 (.a(a), .en(en));
endmodule
module child_par_drv (
    input wire a,
    input logic en
);
  const_child u (.a(a));
  assign a = en ? 1'b0 : 1'bz;
endmodule

// Not coerced: unpacked type
module unpacked_drv (
    input wire a[2],
    input logic v
);
  assign a[0] = v;
  assign a[1] = !v;
endmodule

// verilator lint_on ASSIGNIN

module dut (
    input logic d,
    output logic q
);
  assign q = d;
endmodule

class driver;
  virtual drv_if vif;
  function new(virtual drv_if v);
    vif = v;
  endfunction
  task drive(logic val);
    vif.cb.d <= val;
  endtask
endclass

module t (
    input wire tin
);
  logic clk = 0;
  always #5 clk = ~clk;

  // Clocking drive through a virtual interface reaches the DUT
  wire w;
  logic q;
  drv_if di (.clk(clk), .d(w));
  dut u_dut (.d(w), .q(q));

  // Two instances driving a bit-select each, an instance array driving a
  // concatenation, and a drive with a skew
  wire [1:0] bus;
  drv_if di0 (.clk(clk), .d(bus[0]));
  drv_if di1 (.clk(clk), .d(bus[1]));
  wire da0, da1;
  drv_if dia[1:0] (.clk(clk), .d({da1, da0}));
  wire [1:0] sw;
  skew_if si (.clk(clk), .d(sw[1]));

  // Resolution with another driver, through ports of the parent, from an
  // output port, into a wider net, and into an interface member
  logic en1 = 0, en2 = 0;
  logic [1:0] v1 = 0, v2 = 0;
  wire [1:0] tw;
  wire [1:0] iow;
  wire [1:0] ow;
  wire [3:0] widew;
  net_if ni ();
  assign tw = en2 ? v2 : 2'bzz;
  wrap u_wrap (.a(tw), .en(en1), .v(v1));
  io_wrap u_io (.a(iow), .en(en1), .v(v1));
  out_wrap u_out (.a(ow), .en(en1), .v(v1));
  wire [1:0] onw;
  out_net_wrap u_onw (.o(onw), .en(en1), .v(v1));
  // verilator lint_off WIDTHTRUNC
  tri_drv u_wide (.a(widew), .en(en1), .v(v1));
  // verilator lint_on WIDTHTRUNC
  tri_drv u_if (.a(ni.x), .en(en1), .v(v1));
  tri_drv u_unc (.a(), .en(en1), .v(v1));
  // Instance array connected to a concatenation
  wire [1:0] c0, c1;
  tri_drv u_cat[1:0] (.a({c1, c0}), .en(en1), .v(v1));

  // Not coerced, so connected nets are not driven from inside
  logic [2:0] vv;
  wire [1:0] ovw;
  wire [1:0] idxw;
  logic idx = 0;
  logic cv = 0;
  wire co;
  wire uw[2];
  var_drv u_var (.a(vv[1:0]));
  out_var u_out_var (.o(ovw));
  wire cpw, cpdw;
  child_par u_cp (.a(cpw), .en(en1));
  child_par_drv u_cpd (.a(cpdw), .en(en1));
  // verilator lint_off MULTIDRIVEN
  const_child u_cc (.a(1'b0));
  // verilator lint_on MULTIDRIVEN
  idx_drv u_idx (.a(idxw[idx]));
  const_drv u_const (.a(1'bz), .v(cv), .o(co));
  top_drv u_top (.a(tin));
  wire ncw1, ncw2, ncw3;
  cat_drv u_cat1 (.a({1'b0, ncw1}));
  cat2_drv u_cat2 (.a({ncw2, 1'b0}));
  rep_drv u_rep (.a({2{ncw3}}));
  wire npw1, npw2;
  // An assignment pattern is a read expression, not an inout destination.
  pattern_drv u_pattern (.a('{hi: npw1, lo: npw2}));
  wire ncastw1, ncastw2;
  cast_drv u_cast (.a(pair_t'({ncastw1, ncastw2})));
  unpacked_drv u_unpacked (.a(uw), .v(cv));

  initial begin
    static driver drv = new(di);
    #1;
    `checkh(tw, 2'bzz);
    `checkh(iow, 2'bzz);
    `checkh(ow, 2'bzz);
    `checkh(onw, 2'bzz);
    `checkh(widew, 4'bzzzz);
    `checkh(ni.x, 2'bzz);
    `checkh(cpw, 1'bz);
    `checkh(cpdw, 1'bz);
    en1 = 1;
    v1 = 2'b10;
    cv = 1;
    #1;
    `checkh(tw, 2'b10);
    `checkh(iow, 2'b10);
    `checkh(ow, 2'b10);
    `checkh(onw, 2'b10);
    `checkh(widew, 4'bzz10);
    `checkh(ni.x, 2'b10);
    `checkh(u_unc.a, 2'b10);
    `checkh(c0, 2'b10);
    `checkh(c1, 2'b10);
    `checkh(ncw1, 1'bz);
    `checkh(ncw2, 1'bz);
    `checkh(ncw3, 1'bz);
    `checkh(npw1, 1'bz);
    `checkh(npw2, 1'bz);
    `checkh(ncastw1, 1'bz);
    `checkh(ncastw2, 1'bz);
    `checkh(idxw, 2'bzz);
    `checkh(co, 1'b1);
    `checkh(uw[0], 1'b1);
    `checkh(uw[1], 1'b0);
    `checkh(cpw, 1'b0);
    `checkh(cpdw, 1'b0);
    en1 = 0;
    en2 = 1;
    v2 = 2'b01;
    #1;
    `checkh(tw, 2'b01);
    `checkh(widew, 4'bzzzz);

    @(posedge clk);
    drv.drive(1'b1);
    di0.cb.d <= 1'b1;
    di1.cb.d <= 1'b0;
    dia[0].cb.d <= 1'b1;
    dia[1].cb.d <= 1'b0;
    si.cb.d <= 1'b1;
    repeat (2) @(posedge clk);
    `checkh(w, 1'b1);
    `checkh(q, 1'b1);
    `checkh(bus, 2'b01);
    `checkh(da0, 1'b1);
    `checkh(da1, 1'b0);
    `checkh(sw, 2'b1z);
    drv.drive(1'b0);
    di0.cb.d <= 1'b0;
    di1.cb.d <= 1'b1;
    dia[0].cb.d <= 1'b0;
    dia[1].cb.d <= 1'b1;
    si.cb.d <= 1'b0;
    repeat (2) @(posedge clk);
    `checkh(w, 1'b0);
    `checkh(q, 1'b0);
    `checkh(bus, 2'b10);
    `checkh(da0, 1'b0);
    `checkh(da1, 1'b1);
    `checkh(sw, 2'b0z);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
