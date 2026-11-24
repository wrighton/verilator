// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`ifndef BLK
`define BLK blk
`define BLK_T blk_t
`define BLK_Q blk_q
`define BLK_C blk_c
`endif

module t;
  bit clk = 0;
  bit d = 0;
  wire q, q_t;
  wire y_cls, y_rec, y_dpi, y_vif, y_mem, y_ev, y_wait;
  wire e_ev, e_wait, e_cls, e_rec, e_vif, e_mem, e_lvl, e_mix;
  wire z_dec, z_edge;
  wire k_init, k_const, k_decl;
  `BLK u (
      .clk(clk),
      .d(d),
      .q(q),
      .y_cls(y_cls),
      .y_rec(y_rec),
      .y_dpi(y_dpi),
      .y_vif(y_vif),
      .k_init(k_init),
      .k_const(k_const),
      .k_decl(k_decl)
  );
  `BLK_T u_t (
      .clk(clk),
      .d(d),
      .q(q_t),
      .y_ev(y_ev),
      .y_wait(y_wait),
      .y_mem(y_mem),
      .e_ev(e_ev),
      .e_wait(e_wait),
      .e_cls(e_cls),
      .e_rec(e_rec),
      .e_vif(e_vif),
      .e_mem(e_mem),
      .e_lvl(e_lvl),
      .e_mix(e_mix),
      .z_dec(z_dec),
      .z_edge(z_edge)
  );

  // A clock edge at time zero reaches a registered output in the NBA region, after its initial
  // value
  bit clk_q = 1'b0;
  wire q_q;
  `BLK_Q u_q (
      .clk(clk_q),
      .seq_init__V(1'b1),
      .seq_first__V(1'b1),
      .q_first__V(1'b1),
      .blk_q_protectlib_settle(1'b1),
      .blkqlib_protectlib_settle(1'b1),
      .q(q_q)
  );
  bit q_early;
  initial begin
    #0 clk_q = 1'b1;
    #0 q_early = q_q;
    #1;
    `checkh(q_early, 1'b0);
    `checkh(q_q, 1'b1);
  end
  // Also when the edge is in the Active region of time zero
  bit clk_a = 1'b0;
  wire q_a;
  `BLK_Q u_a (
      .clk(clk_a),
      .seq_init__V(1'b1),
      .seq_first__V(1'b1),
      .q_first__V(1'b1),
      .blk_q_protectlib_settle(1'b1),
      .blkqlib_protectlib_settle(1'b1),
      .q(q_a)
  );
  initial clk_a = 1'b1;
  bit a_early;
  initial begin
    #0 a_early = q_a;
    #1;
    `checkh(a_early, 1'b0);
    `checkh(q_a, 1'b1);
  end
  // A second edge at time zero samples the value from before the first one
  bit clk_b = 1'b0;
  wire q_b;
  `BLK_Q u_b (
      .clk(clk_b),
      .seq_init__V(1'b1),
      .seq_first__V(1'b1),
      .q_first__V(1'b1),
      .blk_q_protectlib_settle(1'b1),
      .blkqlib_protectlib_settle(1'b1),
      .q(q_b)
  );
  bit p_b;
  always_ff @(posedge clk_b) p_b <= q_b;
  initial begin
    clk_b = 1'b1;
    #0 clk_b = 1'b0;
    #0 clk_b = 1'b1;
    #1;
    `checkh(p_b, 1'b0);
    `checkh(q_b, 1'b1);
  end

  // Outputs combinational from clocks of a block reach the parent at once: a clock gate, and an
  // input that is also an event of the block
  bit clk_c = 1'b0;
  bit i_c = 1'b0;
  wire gclk_c, o_c, e_c;
  wire [6:0] cnt_c;
  `BLK_C u_c (
      .clk(clk_c),
      .en(1'b1),
      .i(i_c),
      .clk2(1'b0),
      .d(1'b0),
      .gclk(gclk_c),
      .o(o_c),
      .e(e_c),
      .fclk(),
      .q2(),
      .cnt(cnt_c)
  );
  int a_c = 0;
  int b_c = 0;
  always_ff @(posedge clk_c) a_c <= a_c + 1;
  always_ff @(posedge gclk_c) b_c <= a_c;
  initial begin
    for (int n = 0; n < 2; ++n) begin
      #1 clk_c = 1'b1;
      #1 clk_c = 1'b0;
    end
    `checkh(a_c, 2);
    `checkh(b_c, 1);
    `checkh(cnt_c, 7'd2);
  end
  bit clk_s = 1'b0;
  bit s_c;
  always_ff @(posedge clk_s) s_c <= o_c;
  initial begin
    #1 i_c = 1'b1;
    #0 clk_s = 1'b1;
    #1;
    `checkh(s_c, 1'b1);
    `checkh(e_c, 1'b1);
  end
  // An output of a clock alone fed back to a data input is not a combinational loop
  bit clk_f = 1'b0;
  bit clk2_f = 1'b0;
  wire fclk_f, q2_f;
  `BLK_C u_f (
      .clk(clk_f),
      .en(1'b1),
      .i(1'b0),
      .clk2(clk2_f),
      .d(fclk_f),
      .gclk(),
      .o(),
      .e(),
      .fclk(fclk_f),
      .q2(q2_f),
      .cnt()
  );
  initial begin
    #1 clk_f = 1'b1;
    #0 clk2_f = 1'b1;
    #1;
    `checkh(q2_f, 1'b1);
    clk_f = 1'b0;
    #0 clk2_f = 1'b0;
    #0 clk2_f = 1'b1;
    #1;
    `checkh(q2_f, 1'b0);
  end

  // Outputs not written by clocked logic alone already have their values in the first time step
  bit [2:0] k_zero;
  initial begin
    #0 k_zero = {k_init, k_const, k_decl};
    `checkh(k_zero, 3'b111);
    `checkh({z_dec, z_edge}, 2'b11);
  end

  // Outputs written outside clocked logic follow the input without a clock edge
  initial begin
    #1 d = 1;
    #1;
    `checkh({y_cls, y_rec, y_dpi, y_vif, y_mem, y_ev, y_wait}, 7'h7f);
    `checkh({e_ev, e_wait, e_cls, e_rec, e_vif, e_mem, e_lvl, e_mix}, 8'hff);
    clk = 1;
    #1;
    `checkh(q, 1'b1);
    `checkh(q_t, 1'b1);
    d = 0;
    #1;
    `checkh({y_cls, y_rec, y_dpi, y_vif, y_mem, y_ev, y_wait}, 7'h00);
    `checkh(q, 1'b1);
    `checkh(q_t, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

interface vif_t;
  bit sig;
endinterface

module blk (
    input bit clk,
    input bit d,
    output bit q,
    output bit y_cls,
    output bit y_rec,
    output bit y_dpi,
    output bit y_vif,
    output bit k_init,
    output bit k_const,
    output bit k_decl
);
  /*verilator hier_block*/

  always_ff @(posedge clk) q <= d;

  // Written by a class method
  class Writer;
    function void put(bit x);
      y_cls = x;
    endfunction
  endclass
  Writer writer = new;
  always_comb writer.put(d);

  // Written by a recursive function
  function automatic void drive(input bit x, input int n);
    if (n == 0) y_rec = x;
    else drive(x, n - 1);
  endfunction
  always_comb drive(d, 1);

  // Written by a DPI export, called through a context DPI import
  export "DPI-C" function blk_set_y;
  function void blk_set_y(input bit x);
    y_dpi = x;
  endfunction
  import "DPI-C" context function void blk_call_set_y(input bit x);
  always_comb blk_call_set_y(d);

  // Read from a virtual interface a class method writes
  vif_t vif ();
  class VifWriter;
    virtual vif_t v;
    function new(virtual vif_t v);
      this.v = v;
    endfunction
    function void put(bit x);
      v.sig = x;
    endfunction
  endclass
  VifWriter vwriter = new(vif);
  always_comb vwriter.put(d);
  assign y_vif = vif.sig;

  // Written by an initial block, a constant, and a declaration initializer
  initial k_init = 1'b1;
  assign k_const = 1'b1;
  bit decl = 1'b1;
  assign k_decl = decl;
endmodule

module blk_t (
    input bit clk,
    input bit d,
    output bit q,
    output bit y_ev,
    output bit y_wait,
    output bit y_mem,
    output bit e_ev,
    output bit e_wait,
    output bit e_cls,
    output bit e_rec,
    output bit e_vif,
    output bit e_mem,
    output bit e_lvl,
    output bit e_mix,
    output bit z_dec,
    output bit z_edge
);
  /*verilator hier_block*/

  always_ff @(posedge clk) q <= d;

  // Written by processes waiting on events
  always begin
    @(d);
    y_ev = d;
  end
  initial
    forever begin
      wait (d != y_wait);
      y_wait = d;
    end

  // Read from a member of a class
  class Holder;
    bit last;
  endclass
  Holder holder = new;
  always @* begin
    holder.last = d;
    y_mem = holder.last;
  end

  // Clocked by edges made by processes waiting on events, a class method, a recursive function,
  // a virtual interface a class method writes, and a member of a class
  bit g_ev, g_wait, g_cls, g_rec;
  always begin
    @(d);
    g_ev = d;
  end
  always @(posedge g_ev) e_ev <= 1'b1;
  initial
    forever begin
      wait (d != g_wait);
      g_wait = d;
    end
  always @(posedge g_wait) e_wait <= 1'b1;
  class GWriter;
    function void put(bit x);
      g_cls = x;
    endfunction
  endclass
  GWriter gwriter = new;
  always_comb gwriter.put(d);
  always @(posedge g_cls) e_cls <= 1'b1;
  function automatic void gdrive(input bit x, input int n);
    if (n == 0) g_rec = x;
    else gdrive(x, n - 1);
  endfunction
  always_comb gdrive(d, 1);
  always @(posedge g_rec) e_rec <= 1'b1;
  vif_t gvif ();
  class GVifWriter;
    virtual vif_t v;
    function new(virtual vif_t v);
      this.v = v;
    endfunction
    function void put(bit x);
      v.sig = x;
    endfunction
  endclass
  GVifWriter gvwriter = new(gvif);
  always_comb gvwriter.put(d);
  always @(posedge gvif.sig) e_vif <= 1'b1;
  class Clk;
    bit g;
    function void set(bit x);
      g = x;
    endfunction
  endclass
  Clk gclk = new;
  always_comb gclk.set(d);
  always @(posedge gclk.g) e_mem <= 1'b1;
  // Sensitive to any change, alone and with an edge of an input
  always @(g_wait) e_lvl <= 1'b1;
  always @(posedge clk or g_ev) e_mix <= g_ev;

  // A decode of a register with its implicit initial value, and an output of an edge at time zero
  bit zq;
  always_ff @(posedge clk) zq <= d;
  assign z_dec = !zq;
  bit zg;
  initial zg = 1'b1;
  always @(posedge zg) z_edge = 1'b1;
endmodule

// With ports of the names of signals and functions of the wrapper, in either mode
module blk_q (
    input bit clk,
    input bit seq_init__V,
    input bit seq_first__V,
    input bit q_first__V,
    input bit blk_q_protectlib_settle,
    input bit blkqlib_protectlib_settle,
    output bit q
);
  /*verilator hier_block*/
  always_ff @(posedge clk)
    q <= seq_init__V & seq_first__V & q_first__V & blk_q_protectlib_settle
        & blkqlib_protectlib_settle;
endmodule

module blk_c (
    input bit clk,
    input bit en,
    input bit i,
    input bit clk2,
    input bit d,
    output bit gclk,
    output bit o,
    output bit e,
    output bit fclk,
    output bit q2,
    output bit [6:0] cnt
);
  /*verilator hier_block*/
  always_ff @(posedge clk) cnt <= cnt + 7'd1;
  assign gclk = clk & en;
  assign o = i;
  always @(i) e <= i;
  assign fclk = clk;
  always_ff @(posedge clk2) q2 <= d;
endmodule
