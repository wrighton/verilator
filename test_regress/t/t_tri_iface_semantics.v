// DESCRIPTION: Verilator: Verilog Test module
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// verilator lint_off MULTIDRIVEN

// ---------------- Compare semantics (=== / !==) ----------------
interface ifc_cmp;
  logic we;
  tri [7:0] d;
endinterface

module drv_cmp (
    ifc_cmp io_ifc
);
  assign io_ifc.d = io_ifc.we ? 8'h5A : 8'hzz;
endmodule

module chk_cmp (
    ifc_cmp io_ifc,
    output logic is_z,
    output logic is_5a,
    output logic not_z,
    output logic not_5a
);
  assign is_z = (io_ifc.d === 8'hzz);
  assign is_5a = (io_ifc.d === 8'h5A);
  assign not_z = (io_ifc.d !== 8'hzz);
  assign not_5a = (io_ifc.d !== 8'h5A);
endmodule

interface ifc_cmp_mp;
  logic we;
  tri [7:0] d;
  modport drv_mp(input we, inout d);
  modport chk_mp(input we, inout d);
endinterface

module drv_cmp_mp (
    ifc_cmp_mp.drv_mp io_ifc
);
  assign io_ifc.d = io_ifc.we ? 8'h5A : 8'hzz;
endmodule

module chk_cmp_mp (
    ifc_cmp_mp.chk_mp io_ifc,
    output logic is_z,
    output logic is_5a,
    output logic not_z,
    output logic not_5a
);
  assign is_z = (io_ifc.d === 8'hzz);
  assign is_5a = (io_ifc.d === 8'h5A);
  assign not_z = (io_ifc.d !== 8'hzz);
  assign not_5a = (io_ifc.d !== 8'h5A);
endmodule

module passthru_cmp (
    ifc_cmp io_ifc
);
  drv_cmp u_drv (.*);
endmodule

// ---------------- Mixed local + external contributors ----------------
interface ifc_mix;
  logic we_local;
  logic we_ext;
  tri [7:0] d;
  assign d = we_local ? 8'hA5 : 8'hzz;
endinterface

module drv_mix (
    ifc_mix io_ifc
);
  assign io_ifc.d = io_ifc.we_ext ? 8'h3C : 8'hzz;
endmodule

interface ifc_mix_mp;
  logic we_local;
  logic we_ext;
  tri [7:0] d;
  modport drv_mp(input we_ext, inout d);
  assign d = we_local ? 8'hA5 : 8'hzz;
endinterface

module drv_mix_mp (
    ifc_mix_mp.drv_mp io_ifc
);
  assign io_ifc.d = io_ifc.we_ext ? 8'h3C : 8'hzz;
endmodule

interface ifc_own (
    input logic [14:0] x
);
  wire [14:0] v;
  assign v = x;
endinterface

module drv_own (
    input logic en,
    input logic [14:0] d,
    ifc_own io_ifc
);
  assign io_ifc.v = en ? d : 'z;
endmodule

interface ifc_own_nest (
    input logic en,
    input logic [14:0] x,
    input logic [14:0] d
);
  ifc_own inner (x);
  assign inner.v = en ? d : 'z;
endinterface

// Own driver of the upper bits only
interface ifc_own_hi (
    input logic [7:0] hi
);
  wire [14:0] v;
  assign v[14:7] = hi;
endinterface

// Own driver reading a variable of the interface of a two-state type
interface ifc_own_rd (
    input logic [3:0] a
);
  bit [3:0] q;
  wire [3:0] v;
  assign q = a;
  assign v = q;
endinterface

// Own drivers of overlapping bits that agree, an own driver of an output port, and of a member
// of a packed structure
interface ifc_own_overlap (
    input logic [1:0] a,
    input logic [1:0] b
);
  wire [3:0] v;
  assign v[2:1] = a;
  assign v[1:0] = b;
endinterface

interface ifc_own_port (
    input logic [1:0] a,
    output wire [3:0] v
);
  assign v[1:0] = a;
endinterface

typedef struct packed {
  logic [2:0] hi;
  logic [2:0] lo;
} own_s_t;

interface ifc_own_member (
    input logic [2:0] a
);
  wire own_s_t v;
  assign v.lo = a;
endinterface

// Own driver of the whole net
interface ifc_whole (
    input logic [3:0] x
);
  wire [3:0] v;
  assign v = x;
endinterface

// Own driver of a bit
interface ifc_bit (
    input logic [3:0] x
);
  wire [3:0] v;
  assign v[0] = x[0];
endinterface

// The same drivers in a module as for ifc_whole and ifc_bit
module whole_plain (
    input logic [3:0] x,
    input logic en
);
  wire [3:0] v;
  wire [3:0] b;
  assign v = x;
  assign v = en ? 4'hc : 'z;
  assign b[0] = x[0];
  assign b = 4'h0;
  assign b = en ? 4'h2 : 'z;
endmodule

// A driver from an enclosing interface
interface ifc_inner (
    input logic [3:0] y
);
  wire [7:0] v;
  assign v[7:4] = y;
endinterface

interface ifc_outer (
    input logic [3:0] x,
    input logic [3:0] y
);
  ifc_inner inner (y);
  assign inner.v[3:0] = x;
endinterface

// An own driver with a delay
interface ifc_own_delay (
    input logic a
);
  wire [1:0] v;
  assign #4 v[1] = a;
endinterface

// An own driver reading an undriven net
interface ifc_rd_net;
  wire [3:0] w;
  wire [3:0] v;
  assign v = w;
endinterface

interface ifc_wired (
    input logic a
);
  wand v;
  assign v = a;
endinterface

interface ifc_own_var;
  logic [6:0] q;
  wire [6:0] v;
  assign v = q;
endinterface

// An own driver reading a variable driven through an output port of a nested interface from an
// input port connected to 'z
interface ifc_pass (
    input wire [3:0] i,
    output logic [3:0] o
);
  assign o = i;
endinterface

interface ifc_nest_out;
  logic [3:0] q;
  wire [3:0] v;
  ifc_pass p (
      .i(4'bz),
      .o(q)
  );
  assign v = q;
endinterface

// An input variable port connected to 'z, or to a variable that is 'z
interface ifc_in_zv #(
    parameter int K = 0
) (
    input var logic [3:0] x
);
  wire [3:0] v;
  assign v = x;
endinterface

// An own driver reading a variable written from a wildcard comparison with 'z bits
interface ifc_wild (
    input logic [3:0] x
);
  wire [3:0] v;
  logic b;
  assign b = (x ==? 4'b1z0z);
  assign v = {3'b010, b};
endinterface

// An own driver reading an output variable port
interface ifc_out_src (
    input logic [3:0] x,
    output logic [3:0] q
);
  wire [3:0] v;
  assign q = x;
  assign v = q;
endinterface

// An own driver of a bit of an element of an unpacked net
interface ifc_elem (
    input logic x
);
  wire [3:0] v[2];
  assign v[1][2] = x;
endinterface

// An own driver of the whole net
interface ifc_fixed #(
    parameter int K = 0
) (
    input logic [3:0] x
);
  wire [3:0] v;
  assign v = x;
endinterface

// A driver through an output port
module drv_out (
    input logic en,
    output wire [3:0] o
);
  assign o = en ? 4'ha : 'z;
endmodule

// Own drivers of whole nets with external drivers that are delayed, connected through an output
// port and of some bits, in a module
module fixed_plain (
    input logic en,
    input logic [3:0] x
);
  wire [3:0] d, o, s;
  assign d = x;
  assign o = x;
  assign s = x;
  assign #1 d = en ? 4'h9 : 'z;
  drv_out u_o (
      en,
      o
  );
  assign s[1:0] = en ? 2'b10 : 'z;
endmodule

// A weak own driver
interface ifc_weak (
    input logic [3:0] x
);
  wire [3:0] w;
  assign (weak0, weak1) w = x;
endinterface

// An own driver reading a variable written in a task from a net
interface ifc_task_wr;
  wire [3:0] w;
  logic [3:0] q = 0;
  wire [3:0] v;
  assign v = q;
  task automatic set_q();
    q = w;
  endtask
endinterface

// The same drivers in a module
module task_wr_plain (
    input logic en
);
  wire [3:0] w;
  logic [3:0] q = 0;
  wire [3:0] v;
  assign v = q;
  assign v = en ? 4'h6 : 'z;
  task automatic set_q();
    q = w;
  endtask
endmodule

// An own driver reading a variable written from a member of a class or a virtual interface
interface ifc_own_mem #(
    parameter int K = 0
);
  wire [3:0] n;
  wire [3:0] w;
  logic [3:0] v;
  assign n = v;
endinterface

class mem_t;
  logic [3:0] f;
endclass

module t;
  int pending = 0;  // Test blocks running
  // ---- Compare semantics: basic ----
  ifc_cmp i_cmp ();
  logic is_z, is_5a, not_z, not_5a;
  drv_cmp u_drv_cmp (.io_ifc(i_cmp));
  chk_cmp u_chk_cmp (
      .io_ifc(i_cmp),
      .is_z(is_z),
      .is_5a(is_5a),
      .not_z(not_z),
      .not_5a(not_5a)
  );

  // ---- Compare semantics: modport ----
  ifc_cmp_mp i_cmp_mp ();
  logic mp_is_z, mp_is_5a, mp_not_z, mp_not_5a;
  drv_cmp_mp u_drv_cmp_mp (.io_ifc(i_cmp_mp));
  chk_cmp_mp u_chk_cmp_mp (
      .io_ifc(i_cmp_mp),
      .is_z(mp_is_z),
      .is_5a(mp_is_5a),
      .not_z(mp_not_z),
      .not_5a(mp_not_5a)
  );

  // ---- Compare semantics: deep hierarchy ----
  ifc_cmp i_cmp_deep ();
  logic deep_is_z, deep_is_5a, deep_not_z, deep_not_5a;
  passthru_cmp u_cmp_deep (.io_ifc(i_cmp_deep));
  chk_cmp u_chk_cmp_deep (
      .io_ifc(i_cmp_deep),
      .is_z(deep_is_z),
      .is_5a(deep_is_5a),
      .not_z(deep_not_z),
      .not_5a(deep_not_5a)
  );

  // ---- Mixed contributors ----
  ifc_mix i_mix ();
  drv_mix u_mix (.io_ifc(i_mix));

  ifc_mix_mp i_mix_mp ();
  drv_mix_mp u_mix_mp (.io_ifc(i_mix_mp));

  // Test: own drivers with external drivers: of the whole net, external drivers in a module, the
  // top and an enclosing interface, and an instance nothing drives from outside; of the upper
  // bits, with external drivers of the lower bits through a select and a partly 'z value; reading
  // a variable of the interface; of overlapping bits that agree, of an output port and of a
  // structure member
  logic o_en = 1;
  logic [14:0] o_x = 0;
  logic [14:0] o_d = 0;
  ifc_own i_own_mod (o_x);
  drv_own u_drv_own (
      o_en,
      o_d,
      i_own_mod
  );
  ifc_own i_own_top (o_x);
  assign i_own_top.v = o_en ? o_d : 'z;
  ifc_own_nest i_own_nest (
      o_en,
      o_x,
      o_d
  );
  ifc_own i_own_alone (o_x);
  ifc_own_hi i_own_hs (o_x[14:7]);
  assign i_own_hs.v[6:0] = o_en ? o_d[6:0] : 'z;
  ifc_own_hi i_own_hz (o_x[14:7]);
  assign i_own_hz.v = {8'bz, o_en ? o_d[6:0] : 7'bz};
  ifc_own_rd i_own_rd (4'h6);
  assign i_own_rd.v = o_en ? 4'h6 : 'z;
  ifc_own_overlap i_own_overlap (
      o_x[2:1],
      o_x[1:0]
  );
  assign i_own_overlap.v[3] = o_en ? o_x[2] : 1'bz;
  wire [3:0] e_port;
  ifc_own_port i_own_port (
      o_x[1:0],
      e_port
  );
  assign i_own_port.v[3:2] = o_en ? ~o_x[1:0] : 'z;
  ifc_own_member i_own_member (o_x[2:0]);
  assign i_own_member.v.hi = o_en ? ~o_x[2:0] : 'z;
  initial begin
    ++pending;
    repeat (8) begin
      // Enabled external drivers agree with the own driver
      o_en = 1;
      o_x = 15'($random);
      o_d = o_x;
      #1;
      `checkh(i_own_mod.v, o_x);
      `checkh(i_own_top.v, o_x);
      `checkh(i_own_nest.inner.v, o_x);
      `checkh(i_own_alone.v, o_x);
      `checkh(i_own_hs.v, o_x);
      `checkh(i_own_hz.v, o_x);
      `checkh(i_own_rd.v, 4'h6);
      `checkh(i_own_overlap.v, {o_x[2], o_x[2:0]});
      `checkh(i_own_port.v, {~o_x[1:0], o_x[1:0]});
      `checkh(e_port, {~o_x[1:0], o_x[1:0]});
      `checkh(i_own_member.v, {~o_x[2:0], o_x[2:0]});
      o_en = 0;
      o_d = ~o_x;
      #1;
      `checkh(i_own_mod.v, o_x);
      `checkh(i_own_top.v, o_x);
      `checkh(i_own_nest.inner.v, o_x);
      `checkh(i_own_alone.v, o_x);
      `checkh(i_own_hs.v[14:7], o_x[14:7]);
      `checkh(i_own_hs.v[6:0], 7'bz);
      `checkh(i_own_hz.v[14:7], o_x[14:7]);
      `checkh(i_own_hz.v[6:0], 7'bz);
      `checkh(i_own_rd.v, 4'h6);
      `checkh(i_own_overlap.v[3], 1'bz);
      `checkh(i_own_overlap.v[2:0], o_x[2:0]);
      `checkh(i_own_port.v[3:2], 2'bz);
      `checkh(i_own_member.v.hi, 3'bz);
      `checkh(i_own_member.v.lo, o_x[2:0]);
    end
    --pending;
  end

  // Test: own drivers with a driver from an enclosing interface, with a delay, reading a variable
  // port connected to 'z or to a variable that is 'z, reading a variable driven through an output
  // port that may carry 'z, reading an undriven net, and of a wired net
  logic k_en = 0;
  logic [3:0] k_x = 4'h3;
  logic [3:0] k_y = 4'h9;
  ifc_outer i_outer (
      k_x,
      k_y
  );
  assign i_outer.inner.v = k_en ? 8'h00 : 'z;
  logic k_da = 1;
  ifc_own_delay i_own_delay (k_da);
  logic k_den = 1;
  assign i_own_delay.v[0] = k_den ? 1'b1 : 1'bz;
  logic k_n_en = 1;
  ifc_rd_net i_rd_net ();
  assign i_rd_net.v = k_en ? 4'h3 : 'z;
  ifc_in_zv i_in_zv (4'bz);
  assign i_in_zv.v = k_en ? 4'h5 : 'z;
  logic [3:0] k_vz = 'z;
  ifc_in_zv #(1) i_in_zvar (k_vz);
  assign i_in_zvar.v = k_en ? 4'h5 : 'z;
  ifc_nest_out i_nest_out ();
  assign i_nest_out.v = k_en ? 4'h5 : 'z;
  logic k_a = 1;
  ifc_wired i_wired (k_a);
  assign i_wired.v = k_n_en ? 1'b0 : 1'bz;
  initial begin
    ++pending;
    #1;
    `checkh(i_own_delay.v, 2'bz1);
    #4;
    `checkh(i_own_delay.v, 2'b11);
    repeat (2) begin
      `checkh(i_outer.inner.v, {k_y, k_x});
      `checkh(i_rd_net.v, 4'bz);
      `checkh(i_in_zv.v, 4'bz);
      `checkh(i_in_zvar.v, 4'bz);
      `checkh(i_nest_out.v, 4'bz);
      `checkh(i_wired.v, 1'b0);
      k_x = ~k_x;
      k_y = ~k_y;
      #1;
    end
    --pending;
  end

  // Test: an own driver reading a variable also driven 'z from outside
  logic q_en = 0;
  logic [6:0] q_d = 0;
  ifc_own_var i_own_var ();
  assign i_own_var.v = q_en ? q_d : 'z;
  initial begin
    ++pending;
    i_own_var.q = 'z;
    #1;
    `checkh(i_own_var.v, 7'bz);
    i_own_var.q = 7'h15;
    #1;
    `checkh(i_own_var.v, 7'h15);
    --pending;
  end

  // Test: an own driver of the whole net with an enabled external driver, an own driver of a bit
  // with an external uniform constant and a weak own driver with an enabled external driver
  // resolve as the same drivers in a module; so does an own driver reading a variable written
  // from a wildcard comparison with 'z bits
  logic w_en = 1;
  logic [3:0] w_x = 4'h3;
  ifc_whole i_whole (w_x);
  assign i_whole.v = w_en ? 4'hc : 'z;
  ifc_bit i_bit (w_x);
  assign i_bit.v = 4'h0;
  assign i_bit.v = w_en ? 4'h2 : 'z;
  whole_plain u_whole (
      w_x,
      w_en
  );
  logic [3:0] w_wx = 4'b1000;
  ifc_wild i_wild (w_wx);
  assign i_wild.v = w_en ? 4'h5 : 'z;
  ifc_weak i_weak (w_x);
  assign i_weak.w = w_en ? 4'ha : 'z;
  initial begin
    ++pending;
    #1;
    `checkh(i_whole.v, u_whole.v);
    `checkh(i_bit.v[0], u_whole.b[0]);
    `checkh(i_weak.w, 4'ha);
    `checkh(i_wild.v, 4'h5);
    w_x = 4'h5;
    #1;
    `checkh(i_whole.v, u_whole.v);
    `checkh(i_bit.v[0], u_whole.b[0]);
    `checkh(i_weak.w, 4'ha);
    w_en = 0;
    w_wx = 4'b0001;
    #1;
    `checkh(i_whole.v, u_whole.v);
    `checkh(i_wild.v, 4'h4);
    --pending;
  end

  // Test: own drivers reading a variable written in a task, or written from a member of a class
  // or a virtual interface, resolve as the same drivers in a module; an own driver of a bit of an
  // element of an unpacked net drives the bit; an own driver reading an output variable port
  // connected to a net also driven 'z drives the port's value
  logic d_en = 0;
  ifc_elem i_elem (1'b1);
  logic d_oe = 0;
  wire [3:0] d_n;
  assign d_n = d_oe ? 4'h9 : 'z;
  ifc_out_src i_out_src (
      4'h6,
      d_n
  );
  assign i_out_src.v = d_en ? 4'h3 : 'z;
  ifc_task_wr i_task_wr ();
  assign i_task_wr.v = d_en ? 4'h6 : 'z;
  task_wr_plain u_task_wr (d_en);
  logic m_oe = 1;
  ifc_own_mem i_mem_cls ();
  ifc_own_mem #(1) i_mem_vif ();
  assign i_mem_cls.n = m_oe ? 4'h5 : 'z;
  assign i_mem_vif.n = m_oe ? 4'h5 : 'z;
  virtual ifc_own_mem #(1) m_vif;
  mem_t m_c;
  mem_t m_d;
  initial begin
    ++pending;
    #3;
    `checkh(i_elem.v[1][2], 1'b1);
    `checkh(i_out_src.v, 4'h6);
    i_task_wr.set_q();
    u_task_wr.set_q();
    #1;
    `checkh(i_task_wr.v, u_task_wr.v);
    d_en = 1;
    #3;
    `checkh(i_task_wr.v, u_task_wr.v);
    m_c = new;
    m_d = new;
    m_vif = i_mem_vif;
    m_c.f = i_mem_cls.n;
    i_mem_cls.v = m_d.f;
    i_mem_vif.v = m_vif.w;
    i_mem_cls.v = 4'h3;
    i_mem_vif.v = 4'h3;
    m_oe = 0;
    #1;
    `checkh(i_mem_cls.n, 4'h3);
    `checkh(i_mem_vif.n, 4'h3);
    --pending;
  end

  // Test: with an own driver of the whole net, external drivers that are delayed, connected
  // through an output port or of some bits resolve as in a module where the own driver's bits
  // differ from theirs
  logic g_en = 0;
  logic [3:0] g_x = 4'h5;
  ifc_fixed #(1) i_fx_dly (g_x);
  ifc_fixed #(2) i_fx_port (g_x);
  ifc_fixed #(3) i_fx_sel (g_x);
  assign #1 i_fx_dly.v = g_en ? 4'h9 : 'z;
  drv_out u_fx_port (
      g_en,
      i_fx_port.v
  );
  assign i_fx_sel.v[1:0] = g_en ? 2'b10 : 'z;
  fixed_plain u_fx (
      g_en,
      g_x
  );
  initial begin
    ++pending;
    #2;
    g_en = 1;
    #2;
    `checkh(i_fx_dly.v[3], u_fx.d[3]);
    `checkh(i_fx_port.v[3], u_fx.o[3]);
    `checkh(i_fx_sel.v[1], u_fx.s[1]);
    --pending;
  end

  initial begin
    // ---- Compare semantics ----
    i_cmp.we = 1'b0;
    i_cmp_mp.we = 1'b0;
    i_cmp_deep.we = 1'b0;
    #1;

    `checkh(is_z, 1'b1);
    `checkh(is_5a, 1'b0);
    `checkh(not_z, 1'b0);
    `checkh(not_5a, 1'b1);
    `checkh(mp_is_z, 1'b1);
    `checkh(mp_is_5a, 1'b0);
    `checkh(mp_not_z, 1'b0);
    `checkh(mp_not_5a, 1'b1);
    `checkh(deep_is_z, 1'b1);
    `checkh(deep_is_5a, 1'b0);

    #1;
    i_cmp.we = 1'b1;
    i_cmp_mp.we = 1'b1;
    i_cmp_deep.we = 1'b1;
    #1;

    `checkh(is_z, 1'b0);
    `checkh(is_5a, 1'b1);
    `checkh(not_z, 1'b1);
    `checkh(not_5a, 1'b0);
    `checkh(mp_is_z, 1'b0);
    `checkh(mp_is_5a, 1'b1);
    `checkh(mp_not_z, 1'b1);
    `checkh(mp_not_5a, 1'b0);
    `checkh(deep_is_z, 1'b0);
    `checkh(deep_is_5a, 1'b1);

    #1;
    i_cmp.we = 1'b0;
    i_cmp_mp.we = 1'b0;
    i_cmp_deep.we = 1'b0;
    #1;

    `checkh(is_z, 1'b1);
    `checkh(is_5a, 1'b0);
    `checkh(not_z, 1'b0);
    `checkh(not_5a, 1'b1);
    `checkh(mp_is_z, 1'b1);
    `checkh(mp_is_5a, 1'b0);
    `checkh(mp_not_z, 1'b0);
    `checkh(mp_not_5a, 1'b1);
    `checkh(deep_is_z, 1'b1);
    `checkh(deep_is_5a, 1'b0);

    // ---- Mixed contributors ----
    i_mix.we_local = 1'b0;
    i_mix.we_ext = 1'b0;
    i_mix_mp.we_local = 1'b0;
    i_mix_mp.we_ext = 1'b0;
    #1;

    `checkh(i_mix.d, 8'hzz);
    `checkh(i_mix_mp.d, 8'hzz);

    #1;
    i_mix.we_local = 1'b1;
    i_mix.we_ext = 1'b0;
    i_mix_mp.we_local = 1'b1;
    i_mix_mp.we_ext = 1'b0;
    #1;
    `checkh(i_mix.d, 8'hA5);
    `checkh(i_mix_mp.d, 8'hA5);

    #1;
    i_mix.we_local = 1'b0;
    i_mix.we_ext = 1'b1;
    i_mix_mp.we_local = 1'b0;
    i_mix_mp.we_ext = 1'b1;
    #1;
    `checkh(i_mix.d, 8'h3C);
    `checkh(i_mix_mp.d, 8'h3C);

    #1;
    i_mix.we_local = 1'b1;
    i_mix.we_ext = 1'b1;
    i_mix_mp.we_local = 1'b1;
    i_mix_mp.we_ext = 1'b1;
    #1;
    `checkh(i_mix.d, 8'hBD);
    `checkh(i_mix_mp.d, 8'hBD);

    #1;
    i_mix.we_local = 1'b0;
    i_mix.we_ext = 1'b0;
    i_mix_mp.we_local = 1'b0;
    i_mix_mp.we_ext = 1'b0;
    #1;
    `checkh(i_mix.d, 8'hzz);
    `checkh(i_mix_mp.d, 8'hzz);

    wait (pending == 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
