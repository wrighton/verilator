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

module leaf (
    inout wire [6:0] p,
    input wire local_en,
    output wire [6:0] forwarded
);
  assign p = local_en ? 7'b0010zzz : 7'bzzzzzzz;
  assign forwarded = p;
endmodule

module middle (
    inout wire [14:0] bus,
    input wire local_en,
    output wire [6:0] forwarded
);
  leaf child (
      .p(bus[11:5]),
      .local_en(local_en),
      .forwarded(forwarded)
  );
endmodule

// Value-preserving forwards of a force-capable port, observed only from another module
module forwarding_leaf (
    inout wire [6:0] p,
    input bit sel,
    input bit [2:0] idx
);
  wire [6:0] direct, rotated, chosen, left, right, joined;
  wire [2:0] low;
  wire picked;
  wire [1:0] window;
  assign direct = p;
  assign rotated = {p[3:0], p[6:4]};
  assign low = p[2:0];
  assign picked = p[idx];
  assign window = p[idx+:2];
  assign chosen = sel ? p : 7'h33;
  assign left = p;
  assign right = p;
  assign joined = sel ? left : right;
endmodule

// Forwards of an inout port reaching a forced input port through nets, an output port, or a
// hierarchical reference, which keeps the input port's own net
module chain_input (
    input wire p
);
endmodule

module chain_source (
    inout wire p
);
endmodule

module chain_inout (
    inout wire p
);
endmodule

module chain_hops (
    inout wire src
);
  wire first = src;
  wire second = first;
  chain_input leaf (second);
  wire inout_first = src;
  wire inout_second = inout_first;
  chain_inout inout_leaf (inout_second);
endmodule

module chain_output (
    inout wire src,
    output wire out
);
  assign out = src;
endmodule

// An inout port forwarded through a streaming concatenation, and through an input port of
// another module, to a forced input port
module chain_input2 (
    input wire [1:0] p
);
endmodule

module chain_stream (
    inout wire [1:0] src
);
  wire [1:0] fwd = {<<{src}};
  chain_input2 leaf (fwd);
endmodule

module chain_relay (
    input wire i
);
  wire w = i;
  chain_input leaf (w);
endmodule

module chain_inhop (
    inout wire src
);
  wire a = src;
  chain_relay relay (a);
endmodule

// Forced input ports fed by a plain output, a hierarchical reference to a variable, or a local
// driver, with no inout port behind, which keep their force domain, also in a module another
// instance of which an inout port feeds
module chain_plain_input (
    input wire p
);
endmodule

module chain_plain_out (
    input logic d,
    output wire o
);
  assign o = d;
endmodule

module chain_var_src;
  logic r = 1'b0;
endmodule

module chain_mixed_hops (
    inout wire src
);
  wire a = src;
  chain_plain_input leaf (a);
endmodule

// An inout port an inout port feeds, also instantiated unconnected, which keeps its force domain
module chain_open_inout (
    inout wire p
);
endmodule

module chain_open_hops (
    inout wire src
);
  wire a = src;
  chain_open_inout leaf (a);
endmodule

module chain_bit_input (
    input wire p
);
endmodule

// A bit of an inout port carried to a forced input port through a two-state variable, which is
// never high impedance, or other bits of vectors with a bit from the inout port, which carry
// no bit of it, keep their force domain
module chain_bits (
    inout wire [1:0] src,
    input bit d
);
  bit cast;
  assign cast = src[0];
  wire cast_w = cast;
  chain_bit_input cast_leaf (cast_w);
  wire [1:0] sep;
  assign sep[0] = src[0];
  assign sep[1] = d;
  wire sep_w = sep[1];
  chain_bit_input sep_leaf (sep_w);
  wire [1:0] cat;
  assign cat = {d, src[0]};
  wire cat_w = cat[1];
  chain_bit_input cat_leaf (cat_w);
  wire cat_lhs, cat_unused;
  assign {cat_lhs, cat_unused} = {d, src[0]};
  chain_bit_input cat_lhs_leaf (cat_lhs);
  wire [1:0] ext = {1'b0, src[0]};
  wire ext_w = ext[1];
  chain_bit_input ext_leaf (ext_w);
endmodule

module carry_slice_leaf (
    input wire p
);
endmodule

module carry_sext_leaf (
    input wire p
);
endmodule

module carry_both_leaf (
    input wire p
);
endmodule

module carry_stream_leaf (
    input wire p
);
endmodule

module carry_upper_leaf (
    input wire p
);
endmodule

module carry_sgn_leaf (
    input wire p
);
endmodule

module carry_local_leaf (
    input wire p
);
endmodule

interface carry_if;
  wire n;
endinterface

module carry_signed_src (
    input wire p,
    output wire signed q
);
  assign q = p;
endmodule

module carry_holder;
  wire w;
  carry_local_leaf leaf (w);
endmodule

// A bit of an inout port carried to forced input ports through a bit of a concatenation, the
// sign of a sign extension or of a signed output, a conditional whose arms both carry it, a
// short final slice of a stream, or the bit in range of a select partly out of range. A
// conditional with one arm carrying it, an assignment target partly out of range, and
// hierarchical or interface targets carry none.
module carry_relay (
    inout wire io,
    input bit d,
    input bit sel
);
  wire [1:0] cat = {d, io};
  wire slice = cat[0];
  carry_slice_leaf slice_leaf (slice);
  wire signed [1:0] sio = {io, d};
  wire signed [3:0] sext = 4'(sio);
  wire sext3 = sext[3];
  carry_sext_leaf sext_leaf (sext3);
  wire both = sel ? io : slice;
  carry_both_leaf both_leaf (both);
  wire [2:0] sv = {<<2{{d, d, io}}};
  wire sw = sv[1];
  carry_stream_leaf stream_leaf (sw);
  wire [2:0] top3 = {io, d, d};
  // verilator lint_off SELRANGE
  wire [1:0] upper = top3[2+:2];
  // verilator lint_on SELRANGE
  wire up0 = upper[0];
  carry_upper_leaf upper_leaf (up0);
  wire signed [2:0] sgn3;
  // verilator lint_off WIDTHEXPAND
  // verilator lint_off WIDTHTRUNC
  carry_signed_src sgn_src (
      io,
      sgn3
  );
  // verilator lint_on WIDTHTRUNC
  // verilator lint_on WIDTHEXPAND
  wire sgn2 = sgn3[2];
  carry_sgn_leaf sgn_leaf (sgn2);
  wire live = 1'b1 ? io : d;
  carry_local_leaf live_leaf (live);
  wire dyn = sel ? io : d;
  carry_local_leaf dyn_leaf (dyn);
  wire fsel = 1'b0;
  wire folded = fsel ? io : d;
  carry_local_leaf folded_leaf (folded);
  for (genvar i = 0; i < 2; ++i) begin : g
    wire a = i == 0 ? io : d;
    carry_local_leaf leaf (a);
  end
  wire [1:0] x;
  // verilator lint_off SELRANGE
  assign x[-1+:2] = {d, io};
  // verilator lint_on SELRANGE
  wire oob = x[0];
  carry_local_leaf oob_leaf (oob);
  carry_if ifc ();
  assign ifc.n = io;
  wire ifc_w = ifc.n;
  carry_local_leaf iface_leaf (ifc_w);
  assign t.holder.w = io;
endmodule

module carry_out_src (
    inout wire io,
    output wire q
);
  assign q = io;
endmodule

module carry_wide_leaf (
    input wire [69:0] p
);
endmodule

module carry_rep_leaf (
    input wire [5:0] p
);
endmodule

module carry_ovl_leaf (
    input wire [3:0] p
);
endmodule

module carry_part_leaf (
    input wire [1:0] p
);
endmodule

// Bits of a multi-word inout port carried through reversals, a right stream, replication and
// overlapping writers each carrying them; a vector with other bits, from another source or
// zero-filled, keeps its force domain
module carry_multi (
    inout wire [69:0] io,
    input bit d
);
  wire [69:0] r1 = {<<{io}};
  wire [69:0] r2 = {>>{ {<<{r1}} }};
  carry_wide_leaf wide_leaf (r2);
  wire [5:0] rep = {3{io[1:0]}};
  carry_rep_leaf rep_leaf (rep);
  // verilator lint_off MULTIDRIVEN
  wire [3:0] ovl;
  assign ovl[2:0] = io[2:0];
  assign ovl[3:1] = io[3:1];
  // verilator lint_on MULTIDRIVEN
  carry_ovl_leaf ovl_leaf (ovl);
  wire [1:0] part = {d, io[0]};
  carry_part_leaf part_leaf (part);
  wire [1:0] zext = 2'(io[0]);
  carry_part_leaf zext_leaf (zext);
endmodule

module carry_over_leaf (
    input wire p
);
endmodule

module carry_reqs_leaf (
    input wire p
);
endmodule

module carry_more_leaf (
    input wire p
);
endmodule

module carry_nest_leaf (
    input wire p
);
endmodule

// A value of 4096 runs once its last run, from a conditional, merges with the one before,
// carries the bits of an inout port to a forced input port
module carry_nested (
    inout wire [1:0] io,
    input bit s
);
  wire [8192:0] nest = {s ? io[1] : io[1], {4096{io[0], 1'b0}}};
  wire nest_w = nest[8192];
  carry_nest_leaf nest_leaf (nest_w);
endmodule

// A run needing 64 bits carries the bits of an inout port to a forced input port; a value of
// more than 4096 runs, or a run needing more than 64 bits, carries none, so the forced input
// ports it feeds keep their force domains
module carry_bounds (
    inout wire io,
    input bit d,
    input bit [64:0] s
);
  wire [8193:0] over = {4097{io, 1'b0}};
  wire over_w = over[1];
  carry_over_leaf over_leaf (over_w);
  wire [64:0] a = {65{io}};
  wire reqs_w = s[0] ? a[0] : s[1] ? a[1] : s[2] ? a[2] : s[3] ? a[3] : s[4] ? a[4] :
      s[5] ? a[5] : s[6] ? a[6] : s[7] ? a[7] : s[8] ? a[8] : s[9] ? a[9] : s[10] ? a[10] :
      s[11] ? a[11] : s[12] ? a[12] : s[13] ? a[13] : s[14] ? a[14] : s[15] ? a[15] :
      s[16] ? a[16] : s[17] ? a[17] : s[18] ? a[18] : s[19] ? a[19] : s[20] ? a[20] :
      s[21] ? a[21] : s[22] ? a[22] : s[23] ? a[23] : s[24] ? a[24] : s[25] ? a[25] :
      s[26] ? a[26] : s[27] ? a[27] : s[28] ? a[28] : s[29] ? a[29] : s[30] ? a[30] :
      s[31] ? a[31] : s[32] ? a[32] : s[33] ? a[33] : s[34] ? a[34] : s[35] ? a[35] :
      s[36] ? a[36] : s[37] ? a[37] : s[38] ? a[38] : s[39] ? a[39] : s[40] ? a[40] :
      s[41] ? a[41] : s[42] ? a[42] : s[43] ? a[43] : s[44] ? a[44] : s[45] ? a[45] :
      s[46] ? a[46] : s[47] ? a[47] : s[48] ? a[48] : s[49] ? a[49] : s[50] ? a[50] :
      s[51] ? a[51] : s[52] ? a[52] : s[53] ? a[53] : s[54] ? a[54] : s[55] ? a[55] :
      s[56] ? a[56] : s[57] ? a[57] : s[58] ? a[58] : s[59] ? a[59] : s[60] ? a[60] :
      s[61] ? a[61] : s[62] ? a[62] : a[63];
  carry_reqs_leaf reqs_leaf (reqs_w);
  wire more_w = s[0] ? a[0] : s[1] ? a[1] : s[2] ? a[2] : s[3] ? a[3] : s[4] ? a[4] :
      s[5] ? a[5] : s[6] ? a[6] : s[7] ? a[7] : s[8] ? a[8] : s[9] ? a[9] : s[10] ? a[10] :
      s[11] ? a[11] : s[12] ? a[12] : s[13] ? a[13] : s[14] ? a[14] : s[15] ? a[15] :
      s[16] ? a[16] : s[17] ? a[17] : s[18] ? a[18] : s[19] ? a[19] : s[20] ? a[20] :
      s[21] ? a[21] : s[22] ? a[22] : s[23] ? a[23] : s[24] ? a[24] : s[25] ? a[25] :
      s[26] ? a[26] : s[27] ? a[27] : s[28] ? a[28] : s[29] ? a[29] : s[30] ? a[30] :
      s[31] ? a[31] : s[32] ? a[32] : s[33] ? a[33] : s[34] ? a[34] : s[35] ? a[35] :
      s[36] ? a[36] : s[37] ? a[37] : s[38] ? a[38] : s[39] ? a[39] : s[40] ? a[40] :
      s[41] ? a[41] : s[42] ? a[42] : s[43] ? a[43] : s[44] ? a[44] : s[45] ? a[45] :
      s[46] ? a[46] : s[47] ? a[47] : s[48] ? a[48] : s[49] ? a[49] : s[50] ? a[50] :
      s[51] ? a[51] : s[52] ? a[52] : s[53] ? a[53] : s[54] ? a[54] : s[55] ? a[55] :
      s[56] ? a[56] : s[57] ? a[57] : s[58] ? a[58] : s[59] ? a[59] : s[60] ? a[60] :
      s[61] ? a[61] : s[62] ? a[62] : s[63] ? a[63] : a[64];
  carry_more_leaf more_leaf (more_w);
endmodule

// A forward of a force-capable port with a bit another module writes
module partial_leaf (
    inout wire p
);
  // verilator lint_off MULTIDRIVEN
  wire [1:0] q;
  // verilator lint_on MULTIDRIVEN
  assign q[0] = p;
endmodule

module registered_leaf (
    inout wire [6:0] p,
    input bit clk
);
  logic [6:0] state;
  logic [6:0] continuously_sampled;
  assign continuously_sampled = p;
  initial state = 7'h40;
  always @(posedge clk) state <= p;
endmodule

interface read_if;
  wire [6:0] n;
endinterface

module t;
  logic external_en = 1;
  logic external_partial = 0;
  logic local_en = 0;
  wire [14:0] bus;
  wire [6:0] whole = 7'h11;
  assign bus[11:5] = external_en ? (external_partial ? 7'bzzzz000 : 7'h00) : 7'bzzzzzzz;

  leaf good (
      .p(whole),
      .local_en(1'b0),
      .forwarded()
  );
  wire [6:0] forwarded;
  leaf ordinary (
      .p(bus[11:5]),
      .local_en(local_en),
      .forwarded(forwarded)
  );

  wire [8:0] upper;
  wire [8:0] lower;
  assign {upper[8:5], lower[5:3]} =
      external_en ? (external_partial ? 7'bzzzz000 : 7'h00) : 7'bzzzzzzz;
  wire [6:0] concat_forwarded;
  leaf ordinary_concat (
      .p({upper[8:5], lower[5:3]}),
      .local_en(local_en),
      .forwarded(concat_forwarded)
  );

  wire [14:0] nested_bus;
  assign nested_bus[11:5] = external_en ? (external_partial ? 7'bzzzz000 : 7'h00) : 7'bzzzzzzz;
  wire [6:0] nested_forwarded;
  middle nested (
      .bus(nested_bus),
      .local_en(local_en),
      .forwarded(nested_forwarded)
  );

  tri1 [6:0] pulled_high;
  tri0 [6:0] pulled_low;
  wire [6:0] pulled_high_forwarded, pulled_low_forwarded;
  leaf high (
      .p(pulled_high),
      .local_en(1'b0),
      .forwarded(pulled_high_forwarded)
  );
  leaf low (
      .p(pulled_low),
      .local_en(1'b0),
      .forwarded(pulled_low_forwarded)
  );

  bit sample_clk = 0;
  wire [6:0] sampled_net = 7'h03;
  registered_leaf sampler (
      .p(sampled_net),
      .clk(sample_clk)
  );
  initial begin
    #1 force sampler.p = 7'h01;
    #0.5;
    `checkh(sampler.continuously_sampled, 7'h01);
    #0.5 sample_clk = 1;
    #1;
    `checkh(sampler.state, 7'h01);
    release sampler.p;
    sample_clk = 0;
    #1 sample_clk = 1;
    #1;
    `checkh(sampler.state, 7'h03);
    `checkh(sampler.continuously_sampled, 7'h03);
    force sampler.p = 7'bzzzzzzz;
    #1;
    `checkh(sampler.p === 7'bzzzzzzz, 1'b1);
    release sampler.p;
    #1;
    `checkh(sampler.p === 7'bzzzzzzz, 1'b0);
    `checkh(sampler.continuously_sampled, 7'h03);
  end

  // An interface net connection reads the resolved interface net.
  read_if ifc ();
  assign ifc.n = external_en ? 7'h00 : 7'bzzzzzzz;
  wire [6:0] iface_forwarded;
  leaf iface_ordinary (
      .p(ifc.n),
      .local_en(1'b0),
      .forwarded(iface_forwarded)
  );
  initial begin
    #1.5;
    `checkh(iface_forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(iface_forwarded, 7'h00);
    #1;
    `checkh(iface_forwarded === 7'bzzzzzzz, 1'b1);
  end

  // A parent force of a pulled net overrides its pulls only while forced.
  wire [6:0] bit_pulled;
  pullup (bit_pulled[6]);
  pullup (bit_pulled[5]);
  pulldown (bit_pulled[1]);
  pulldown (bit_pulled[0]);
  tri1 [6:0] forced_high;
  tri0 [6:0] forced_low;
  wire [6:0] bit_pulled_forwarded, forced_high_forwarded, forced_low_forwarded;
  leaf bit_pulled_leaf (
      .p(bit_pulled),
      .local_en(1'b0),
      .forwarded(bit_pulled_forwarded)
  );
  leaf forced_high_leaf (
      .p(forced_high),
      .local_en(1'b0),
      .forwarded(forced_high_forwarded)
  );
  leaf forced_low_leaf (
      .p(forced_low),
      .local_en(1'b0),
      .forwarded(forced_low_forwarded)
  );
  initial begin
    #1.5;
    `checkh(bit_pulled_leaf.p === 7'b11zzz00, 1'b1);
    `checkh(bit_pulled_forwarded === 7'b11zzz00, 1'b1);
    `checkh(forced_high_forwarded === 7'h7f, 1'b1);
    `checkh(forced_low_forwarded === 7'h00, 1'b1);
    force bit_pulled = 7'b0z1z0z1;
    force forced_high = 7'bz0z1z0z;
    force forced_low = 7'b1z0z1z0;
    #0.5;
    `checkh(bit_pulled_leaf.p === 7'b0z1z0z1, 1'b1);
    `checkh(bit_pulled_forwarded === 7'b0z1z0z1, 1'b1);
    `checkh(forced_high_forwarded === 7'bz0z1z0z, 1'b1);
    `checkh(forced_low_forwarded === 7'b1z0z1z0, 1'b1);
    release bit_pulled;
    release forced_high;
    release forced_low;
    #0.5;
    `checkh(bit_pulled_leaf.p === 7'b11zzz00, 1'b1);
    `checkh(bit_pulled_forwarded === 7'b11zzz00, 1'b1);
    `checkh(forced_high_forwarded === 7'h7f, 1'b1);
    `checkh(forced_low_forwarded === 7'h00, 1'b1);
    force bit_pulled[5:1] = 5'bz10z1;
    force forced_high[3:2] = 2'bz0;
    #0.5;
    `checkh(bit_pulled_forwarded === 7'b1z10z10, 1'b1);
    `checkh(forced_high_forwarded === 7'b111z011, 1'b1);
    release bit_pulled[5:1];
    release forced_high[3:2];
    #0.5;
    `checkh(bit_pulled_leaf.p === 7'b11zzz00, 1'b1);
    `checkh(bit_pulled_forwarded === 7'b11zzz00, 1'b1);
    `checkh(forced_high_forwarded === 7'h7f, 1'b1);
    `checkh(forced_low_forwarded === 7'h00, 1'b1);
  end

  bit fwd_en = 1, fwd_sel = 1;
  bit [2:0] fwd_idx = 3'd2;
  logic [6:0] fwd_raw = 7'h00;
  wire [6:0] fwd_net;
  assign fwd_net = fwd_en ? fwd_raw : 7'bzzzzzzz;
  forwarding_leaf fwd (
      .p(fwd_net),
      .sel(fwd_sel),
      .idx(fwd_idx)
  );
  wire [6:0] fwd_other_net = 7'h4c;
  forwarding_leaf fwd_other (
      .p(fwd_other_net),
      .sel(1'b1),
      .idx(3'd0)
  );
  task automatic check_forwarded(logic [6:0] expected);
    `checkh(fwd.direct, expected);
    `checkh(fwd.rotated, {expected[3:0], expected[6:4]});
    `checkh(fwd.low, expected[2:0]);
    `checkh(fwd.picked, expected[fwd_idx]);
    `checkh(fwd.window, expected[fwd_idx+:2]);
    `checkh(fwd.joined, expected);
  endtask
  initial begin
    #1.5;
    // Externally driven values, including zero, are not high impedance.
    `checkh(fwd.direct === 7'bzzzzzzz, 1'b0);
    `checkh(fwd.rotated === 7'bzzzzzzz, 1'b0);
    `checkh(fwd.low === 3'bzzz, 1'b0);
    `checkh(fwd.picked === 1'bz, 1'b0);
    `checkh(fwd.window === 2'bzz, 1'b0);
    `checkh(fwd.chosen === 7'bzzzzzzz, 1'b0);
    `checkh(fwd.joined === 7'bzzzzzzz, 1'b0);
    check_forwarded(7'h00);
    `checkh(fwd.chosen, 7'h00);
    fwd_raw = 7'h55;
    #0.1;
    check_forwarded(7'h55);
    force fwd.p = 7'bzzzzzzz;
    #0.1;
    `checkh(fwd.direct === 7'bzzzzzzz, 1'b1);
    `checkh(fwd.rotated === 7'bzzzzzzz, 1'b1);
    `checkh(fwd.low === 3'bzzz, 1'b1);
    `checkh(fwd.picked === 1'bz, 1'b1);
    `checkh(fwd.window === 2'bzz, 1'b1);
    `checkh(fwd.chosen === 7'bzzzzzzz, 1'b1);
    `checkh(fwd.joined === 7'bzzzzzzz, 1'b1);
    fwd_sel = 0;
    #0.1;
    `checkh(fwd.chosen, 7'h33);
    `checkh(fwd.chosen === 7'bzzzzzzz, 1'b0);
    `checkh(fwd.joined === 7'bzzzzzzz, 1'b1);
    force fwd.p = 7'h2a;
    #0.1;
    check_forwarded(7'h2a);
    `checkh(fwd.joined === 7'bzzzzzzz, 1'b0);
    // Mixed driven and high-impedance bits keep their positions
    fwd_sel = 1;
    force fwd.p = 7'bz0z1zz0;
    #0.1;
    `checkh(fwd.direct === 7'bz0z1zz0, 1'b1);
    `checkh(fwd.rotated === 7'b1zz0z0z, 1'b1);
    `checkh(fwd.low === 3'bzz0, 1'b1);
    `checkh(fwd.picked === 1'bz, 1'b1);
    `checkh(fwd.window === 2'b1z, 1'b1);
    `checkh(fwd.chosen === 7'bz0z1zz0, 1'b1);
    `checkh(fwd.joined === 7'bz0z1zz0, 1'b1);
    force fwd.p = 7'b1zz0z01;
    fwd_idx = 3'd3;
    #0.1;
    `checkh(fwd.direct === 7'b1zz0z01, 1'b1);
    `checkh(fwd.rotated === 7'b0z011zz, 1'b1);
    `checkh(fwd.low === 3'bz01, 1'b1);
    `checkh(fwd.picked === 1'b0, 1'b1);
    `checkh(fwd.window === 2'bz0, 1'b1);
    `checkh(fwd.chosen === 7'b1zz0z01, 1'b1);
    `checkh(fwd.joined === 7'b1zz0z01, 1'b1);
    release fwd.p;
    #0.1;
    check_forwarded(7'h55);
    `checkh(fwd.direct === 7'bzzzzzzz, 1'b0);
    `checkh(fwd.window === 2'bzz, 1'b0);
    fwd_en = 0;
    #0.1;
    `checkh(fwd.direct === 7'bzzzzzzz, 1'b1);
    `checkh(fwd.rotated === 7'bzzzzzzz, 1'b1);
    `checkh(fwd.low === 3'bzzz, 1'b1);
    `checkh(fwd.picked === 1'bz, 1'b1);
    `checkh(fwd.window === 2'bzz, 1'b1);
    `checkh(fwd.chosen === 7'bzzzzzzz, 1'b1);
    `checkh(fwd.joined === 7'bzzzzzzz, 1'b1);
    // Another instance of the module keeps its own driven connection.
    `checkh(fwd_other.direct, 7'h4c);
    `checkh(fwd_other.direct === 7'bzzzzzzz, 1'b0);
    `checkh(fwd_other.picked === 1'bz, 1'b0);
    `checkh(fwd_other.joined === 7'bzzzzzzz, 1'b0);
  end

  bit chain_en = 0;
  wire chain_hop_net = chain_en ? 1'b1 : 1'bz;
  chain_hops hops (chain_hop_net);
  wire chain_out_src = chain_en ? 1'b1 : 1'bz;
  wire chain_out;
  chain_output out_h (
      chain_out_src,
      chain_out
  );
  chain_input out_leaf (chain_out);
  wire chain_xref_net = chain_en ? 1'b1 : 1'bz;
  chain_source xref_src (chain_xref_net);
  wire chain_xref = xref_src.p;
  chain_input xref_leaf (chain_xref);
  wire chain_out_inout_src = chain_en ? 1'b1 : 1'bz;
  wire chain_out_inout;
  chain_output out_inout_h (
      chain_out_inout_src,
      chain_out_inout
  );
  chain_inout out_inout_leaf (chain_out_inout);
  wire chain_xref_inout_net = chain_en ? 1'b1 : 1'bz;
  chain_source xref_inout_src (chain_xref_inout_net);
  wire chain_xref_inout = xref_inout_src.p;
  chain_inout xref_inout_leaf (chain_xref_inout);
  wire [1:0] chain_stream_net = chain_en ? 2'b10 : 2'bzz;
  chain_stream stream_h (chain_stream_net);
  wire chain_inhop_net = chain_en ? 1'b1 : 1'bz;
  chain_inhop inhop_h (chain_inhop_net);
  initial begin
    #1.5;
    `checkh(stream_h.leaf.p === 2'bzz, 1'b1);
    `checkh(inhop_h.relay.leaf.p === 1'bz, 1'b1);
    #0.3;
    `checkh(stream_h.leaf.p, 2'b01);
    `checkh(inhop_h.relay.leaf.p, 1'b1);
  end
  logic plain_d = 1'b0;
  wire plain_on;
  chain_plain_out plain_out_h (
      plain_d,
      plain_on
  );
  chain_plain_input plain_leaf (plain_on);
  chain_plain_input plain_sibling (plain_on);
  chain_var_src var_src ();
  wire plain_xw = var_src.r;
  chain_plain_input var_leaf (plain_xw);
  wire plain_local;
  assign plain_local = plain_d;
  chain_plain_input local_leaf (plain_local);
  wire chain_mixed_net = chain_en ? 1'b1 : 1'bz;
  chain_mixed_hops mixed_h (chain_mixed_net);
  initial begin
    #1;
    `checkh(plain_leaf.p === 1'bz, 1'b0);
    `checkh(plain_sibling.p === 1'bz, 1'b0);
    `checkh(plain_on === 1'bz, 1'b0);
    `checkh(var_leaf.p === 1'bz, 1'b0);
    `checkh(local_leaf.p === 1'bz, 1'b0);
    force plain_leaf.p = 1'b1;
    force var_leaf.p = 1'b1;
    force local_leaf.p = 1'b1;
    #0.1;
    `checkh(plain_sibling.p, 1'b1);
    `checkh(plain_on, 1'b1);
    `checkh(plain_xw, 1'b1);
    `checkh(plain_local, 1'b1);
    release plain_leaf.p;
    release var_leaf.p;
    release local_leaf.p;
    #0.1;
    `checkh(plain_leaf.p, 1'b0);
    `checkh(plain_leaf.p === 1'bz, 1'b0);
    `checkh(var_leaf.p === 1'bz, 1'b0);
    `checkh(local_leaf.p === 1'bz, 1'b0);
  end
  wire chain_open_net = chain_en ? 1'b1 : 1'bz;
  chain_open_hops open_hops (chain_open_net);
  chain_open_inout open_leaf (.p());
  initial begin
    #1;
    `checkh(open_leaf.p === 1'bz, 1'b1);
    force open_leaf.p = 1'b0;
    #0.1;
    `checkh(open_leaf.p, 1'b0);
    release open_leaf.p;
    #0.1;
    `checkh(open_leaf.p === 1'bz, 1'b1);
  end
  initial begin
    #2.5;
    `checkh(stream_h.leaf.p, 2'b01);
    `checkh(inhop_h.relay.leaf.p, 1'b1);
    force stream_h.leaf.p = 2'b10;
    force inhop_h.relay.leaf.p = 1'b0;
    force mixed_h.leaf.p = 1'b0;
    force open_hops.leaf.p = 1'b0;
    #0.1;
    `checkh(stream_h.leaf.p, 2'b10);
    `checkh(inhop_h.relay.leaf.p, 1'b0);
    `checkh(mixed_h.leaf.p, 1'b0);
    `checkh(open_hops.leaf.p, 1'b0);
    release stream_h.leaf.p;
    release inhop_h.relay.leaf.p;
    release mixed_h.leaf.p;
    release open_hops.leaf.p;
    #0.1;
    `checkh(stream_h.leaf.p, 2'b01);
    `checkh(inhop_h.relay.leaf.p, 1'b1);
  end
  bit bits_en = 1, bits_d = 1;
  wire [1:0] bits_net = bits_en ? {bits_d, bits_d} : 2'bzz;
  chain_bits bits_h (
      bits_net,
      bits_d
  );
  task automatic check_bits(logic [4:0] expected);
    `checkh({bits_h.cast_leaf.p, bits_h.sep_leaf.p, bits_h.cat_leaf.p, bits_h.cat_lhs_leaf.p,
             bits_h.ext_leaf.p}, expected);
    `checkh({bits_h.cast_leaf.p === 1'bz, bits_h.sep_leaf.p === 1'bz,
             bits_h.cat_leaf.p === 1'bz, bits_h.cat_lhs_leaf.p === 1'bz,
             bits_h.ext_leaf.p === 1'bz}, 5'b00000);
  endtask
  initial begin
    #1;
    check_bits(5'b11110);
    force bits_h.cast_leaf.p = 1'b0;
    force bits_h.sep_leaf.p = 1'b0;
    force bits_h.cat_leaf.p = 1'b0;
    force bits_h.cat_lhs_leaf.p = 1'b0;
    force bits_h.ext_leaf.p = 1'b1;
    #0.1;
    check_bits(5'b00001);
    release bits_h.cast_leaf.p;
    release bits_h.sep_leaf.p;
    release bits_h.cat_leaf.p;
    release bits_h.cat_lhs_leaf.p;
    release bits_h.ext_leaf.p;
    #0.1;
    check_bits(5'b11110);
    bits_en = 0;
    #0.1;
    check_bits(5'b01110);
    bits_d = 0;
    #0.1;
    check_bits(5'b00000);
  end
  bit carry_en = 1, carry_d = 0, carry_sel = 0;
  wire carry_net = carry_en ? 1'b1 : 1'bz;
  carry_relay relay (
      carry_net,
      carry_d,
      carry_sel
  );
  carry_holder holder ();
  // The bit a narrower output fills carries nothing
  wire ext_net = carry_en ? 1'b1 : 1'bz;
  wire [1:0] ext_a;
  // verilator lint_off WIDTHTRUNC
  carry_out_src ext_src (
      ext_net,
      ext_a
  );
  // verilator lint_on WIDTHTRUNC
  wire ext_w = ext_a[1];
  carry_local_leaf ext_leaf (ext_w);
  // Leaves reading a local value, which is never high impedance
  task automatic check_local(logic value);
    `checkh({relay.dyn_leaf.p, relay.folded_leaf.p, relay.g[1].leaf.p, relay.oob_leaf.p,
             ext_leaf.p, ext_w}, {{5{value}}, 1'b0});
    `checkh({relay.dyn_leaf.p === 1'bz, relay.folded_leaf.p === 1'bz,
             relay.g[1].leaf.p === 1'bz, relay.oob_leaf.p === 1'bz, ext_leaf.p === 1'bz},
            5'b00000);
  endtask
  // Leaves fed from the inout port, as without force domains
  `define CARRIED {relay.slice_leaf.p, relay.sext_leaf.p, relay.both_leaf.p, \
      relay.stream_leaf.p, relay.upper_leaf.p, relay.sgn_leaf.p}
  `define CARRIED_Z {relay.slice_leaf.p === 1'bz, relay.sext_leaf.p === 1'bz, \
      relay.both_leaf.p === 1'bz, relay.stream_leaf.p === 1'bz, relay.upper_leaf.p === 1'bz, \
      relay.sgn_leaf.p === 1'bz}
  // Leaves of hierarchical or interface targets, with the reads of a force domain
  `define DOMAIN {holder.leaf.p, relay.iface_leaf.p}
  `define DOMAIN_Z {holder.leaf.p === 1'bz, relay.iface_leaf.p === 1'bz}
  initial begin
    #1;
    check_local(1'b0);
    `checkh(`CARRIED, 6'b111111);
    `checkh(`CARRIED_Z, 6'b000000);
    `checkh(`DOMAIN, 2'b11);
    `checkh(`DOMAIN_Z, 2'b00);
    force relay.slice_leaf.p = 1'b0;
    force relay.sext_leaf.p = 1'b0;
    force relay.both_leaf.p = 1'b0;
    force relay.stream_leaf.p = 1'b0;
    force relay.upper_leaf.p = 1'b0;
    force relay.sgn_leaf.p = 1'b0;
    force holder.leaf.p = 1'b0;
    force relay.iface_leaf.p = 1'b0;
    force relay.live_leaf.p = 1'b0;
    force relay.g[0].leaf.p = 1'b0;
    force relay.dyn_leaf.p = 1'b1;
    force relay.folded_leaf.p = 1'b1;
    force relay.g[1].leaf.p = 1'b1;
    force relay.oob_leaf.p = 1'b1;
    force ext_leaf.p = 1'b1;
    #0.1;
    check_local(1'b1);
    `checkh(`CARRIED, 6'b000000);
    `checkh({`DOMAIN, relay.live_leaf.p, relay.g[0].leaf.p}, 4'b0000);
    release relay.slice_leaf.p;
    release relay.sext_leaf.p;
    release relay.both_leaf.p;
    release relay.stream_leaf.p;
    release relay.upper_leaf.p;
    release relay.sgn_leaf.p;
    release holder.leaf.p;
    release relay.iface_leaf.p;
    release relay.live_leaf.p;
    release relay.g[0].leaf.p;
    release relay.dyn_leaf.p;
    release relay.folded_leaf.p;
    release relay.g[1].leaf.p;
    release relay.oob_leaf.p;
    release ext_leaf.p;
    #0.1;
    check_local(1'b0);
    `checkh(`CARRIED, 6'b111111);
    `checkh(`DOMAIN, 2'b11);
    carry_en = 0;
    #0.1;
    check_local(1'b0);
    `checkh(`CARRIED_Z, 6'b111111);
    `checkh(`DOMAIN_Z, 2'b11);
  end
  bit multi_en = 1, multi_d = 1;
  wire [69:0] multi_net = multi_en ? {70{1'b1}} : 'z;
  carry_multi multi (
      multi_net,
      multi_d
  );
  `define MULTI {multi.wide_leaf.p, multi.rep_leaf.p, multi.ovl_leaf.p}
  initial begin
    #1;
    `checkh(`MULTI, {80{1'b1}});
    `checkh({multi.part_leaf.p, multi.zext_leaf.p}, 4'b1101);
    force multi.wide_leaf.p = {35{2'b10}};
    force multi.rep_leaf.p = 6'h12;
    force multi.ovl_leaf.p = 4'h5;
    force multi.part_leaf.p = 2'b00;
    force multi.zext_leaf.p = 2'b10;
    #0.1;
    `checkh(`MULTI, {{35{2'b10}}, 6'h12, 4'h5});
    `checkh({multi.part_leaf.p, multi.zext_leaf.p}, 4'b0010);
    release multi.wide_leaf.p;
    release multi.rep_leaf.p;
    release multi.ovl_leaf.p;
    release multi.part_leaf.p;
    release multi.zext_leaf.p;
    #0.1;
    `checkh(`MULTI, {80{1'b1}});
    multi_en = 0;
    #0.1;
    `checkh({multi.wide_leaf.p === {70{1'bz}}, multi.rep_leaf.p === 6'bz,
             multi.ovl_leaf.p === 4'bz}, 3'b111);
  end
  bit [64:0] bounds_s = '0;
  carry_bounds bounds (
      carry_net,
      carry_d,
      bounds_s
  );
  // A port fed from the inout port reads a forced value of its own, a port of a force domain
  // shares it with its connection
  wire [1:0] nested_net = carry_en ? 2'b11 : 2'bzz;
  carry_nested nest_relay (
      nested_net,
      carry_d
  );
  `define BOUNDS_W {nest_relay.nest_w, bounds.over_w, bounds.reqs_w, bounds.more_w}
  initial begin
    #1;
    `checkh(`BOUNDS_W, 4'b1111);
    force nest_relay.nest_leaf.p = 1'b0;
    force bounds.over_leaf.p = 1'b0;
    force bounds.reqs_leaf.p = 1'b0;
    force bounds.more_leaf.p = 1'b0;
    #0.05;
    `checkh({nest_relay.nest_leaf.p, bounds.over_leaf.p, bounds.reqs_leaf.p, bounds.more_leaf.p},
            4'b0000);
    `checkh(`BOUNDS_W, 4'b1010);
    release nest_relay.nest_leaf.p;
    release bounds.over_leaf.p;
    release bounds.reqs_leaf.p;
    release bounds.more_leaf.p;
    #0.05;
    `checkh(`BOUNDS_W, 4'b1111);
  end
  // Forces of inout ports fed from inout ports, never executed: executing one is unsupported,
  // as without force domains
  task automatic chain_force_unused;
    force hops.inout_leaf.p = 1'b0;
    force out_inout_leaf.p = 1'b0;
    force xref_inout_leaf.p = 1'b0;
  endtask
  initial begin
    #1.5;
    `checkh(hops.inout_leaf.p === 1'bz, 1'b1);
    `checkh(out_inout_leaf.p === 1'bz, 1'b1);
    `checkh(xref_inout_leaf.p === 1'bz, 1'b1);
    #0.3;
    `checkh(hops.inout_leaf.p, 1'b1);
    `checkh(out_inout_leaf.p, 1'b1);
    `checkh(xref_inout_leaf.p, 1'b1);
  end
  initial begin
    #1.5;
    `checkh(hops.leaf.p === 1'bz, 1'b1);
    `checkh(out_leaf.p === 1'bz, 1'b1);
    `checkh(xref_leaf.p === 1'bz, 1'b1);
    force hops.leaf.p = 1'b0;
    force out_leaf.p = 1'b0;
    force xref_leaf.p = 1'b0;
    #0.1;
    `checkh(hops.leaf.p, 1'b0);
    `checkh(out_leaf.p, 1'b0);
    `checkh(xref_leaf.p, 1'b0);
    release hops.leaf.p;
    release out_leaf.p;
    release xref_leaf.p;
    #0.1;
    `checkh(hops.leaf.p === 1'bz, 1'b1);
    `checkh(out_leaf.p === 1'bz, 1'b1);
    `checkh(xref_leaf.p === 1'bz, 1'b1);
    chain_en = 1;
    #0.1;
    `checkh(hops.leaf.p, 1'b1);
    `checkh(out_leaf.p, 1'b1);
    `checkh(xref_leaf.p, 1'b1);
    force hops.leaf.p = 1'b0;
    force xref_leaf.p = 1'b0;
    #0.1;
    `checkh(hops.leaf.p, 1'b0);
    `checkh(xref_leaf.p, 1'b0);
    release hops.leaf.p;
    release xref_leaf.p;
    #0.1;
    `checkh(hops.leaf.p, 1'b1);
    `checkh(xref_leaf.p, 1'b1);
  end

  bit part_data = 1;
  wire part_net;
  assign part_net = part_data;
  partial_leaf part (part_net);
  assign part.q[1] = 1'b0;
  task automatic part_force_unused;
    force part.p = 1'b0;
  endtask
  initial begin
    #1.5;
    `checkh(part.q, 2'b01);
    `checkh(part.q[0] === 1'bz, 1'b0);
  end

  task automatic check_ordinary(logic [6:0] expected);
    `checkh(ordinary.p, expected);
    `checkh(ordinary.forwarded, expected);
    `checkh(forwarded, expected);
    `checkh(concat_forwarded, expected);
    `checkh(nested_forwarded, expected);
  endtask

  initial begin
    #1;
    force good.p = 7'h12;
    // Externally driven zero is distinct from a floating connection.
    #1;
    `checkh(ordinary.p === 7'bzzzzzzz, 1'b0);
    `checkh(ordinary.forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(concat_forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(nested_forwarded === 7'bzzzzzzz, 1'b0);
    check_ordinary(7'h00);
    `checkh(whole, 7'h12);
    `checkh(pulled_high_forwarded, 7'h7f);
    `checkh(pulled_low_forwarded, 7'h00);
    `checkh(pulled_high_forwarded === 7'bzzzzzzz, 1'b0);
    `checkh(pulled_low_forwarded === 7'bzzzzzzz, 1'b0);

    external_en = 0;
    #1;
    `checkh(ordinary.p === 7'bzzzzzzz, 1'b1);
    `checkh(ordinary.forwarded === 7'bzzzzzzz, 1'b1);
    `checkh(forwarded === 7'bzzzzzzz, 1'b1);
    `checkh(concat_forwarded === 7'bzzzzzzz, 1'b1);
    `checkh(nested_forwarded === 7'bzzzzzzz, 1'b1);

    local_en = 1;
    #1;
    `checkh(ordinary.p === 7'b0010zzz, 1'b1);
    `checkh(ordinary.forwarded === 7'b0010zzz, 1'b1);
    `checkh(forwarded === 7'b0010zzz, 1'b1);
    `checkh(concat_forwarded === 7'b0010zzz, 1'b1);
    `checkh(nested_forwarded === 7'b0010zzz, 1'b1);

    external_partial = 1;
    external_en = 1;
    #1;
    `checkh(ordinary.p === 7'b0010zzz, 1'b0);
    `checkh(ordinary.forwarded === 7'b0010zzz, 1'b0);
    `checkh(forwarded === 7'b0010zzz, 1'b0);
    check_ordinary(7'h10);

    release good.p;
    #1;
    `checkh(whole, 7'h11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
