// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// Check the z bits and the one bits of a 2-bit net under a mask
`define checkz(gotv,expv,carev) `checkh({gotv[1] === 1'bz, gotv[0] === 1'bz, gotv[1] === 1'b1, gotv[0] === 1'b1} & (carev), (expv) & (carev))
// verilog_format: on

// Each kind of force value forced on interface strength nets that are always driven or
// floating, directly and from a task. Cells reported unsupported are in
// t_tri_iface_force_unsup.

// An always driven (weak plus a strong driver) or floating interface strength net
interface tgt_if #(
    parameter bit FLOATING = 0
) (
    input bit drv_on
);
  wire [1:0] value;
  if (FLOATING) begin : g_floating
    assign (weak0, weak1) value = drv_on ? 2'b00 : 2'bzz;
  end else begin : g_always
    assign (weak0, weak1) value = 2'b10;
    assign value = drv_on ? 2'b01 : 2'bzz;
  end
endinterface

interface src_if;
  logic [1:0] l4 = 2'b11;
  bit [1:0] b2 = 2'b11;
  wire [1:0] w4 = l4;
  bit ten = 1'b0;
  wire [1:0] wt;
  assign (weak0, weak1) wt = ten ? 2'b10 : 2'bzz;
  tri0 [1:0] ps;
  assign (weak0, weak1) ps = 2'b00;
  wire [1:0] fs;
  assign (weak0, weak1) fs = 2'b10;
endinterface

module tri_drv (
    output wire [1:0] o,
    input bit en
);
  assign o = en ? 2'b11 : 2'bzz;
endmodule

module const_drv (
    output wire [1:0] o
);
  assign o = 2'b10;
endmodule

// verilog_format: off
`define FORCE_RELEASE(rhs) \
    if (TASK) begin : g_task \
      task automatic set_force; force tgt.value = rhs; endtask \
      task automatic clear_force; release tgt.value; endtask \
      always @(force_ev) set_force(); \
      always @(release_ev) clear_force(); \
    end else begin : g_direct \
      always @(force_ev) force tgt.value = rhs; \
      always @(release_ev) release tgt.value; \
    end
// verilog_format: on

// Force one kind of value on the target net, change the net's driver and the value, then
// release it (IEEE 1800-2023 10.6.2). F and F2 are the forced values before and after the
// change as {z bits, one bits}, with FC and F2C masking the bits that only need to be driven.
module m #(
    parameter int KIND = 0,
    parameter bit FLOATING = 0,
    parameter bit TASK = 0,
    parameter bit [3:0] F = 0,
    parameter bit [3:0] FC = 0,
    parameter bit [3:0] F2 = 0,
    parameter bit [3:0] F2C = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  event force_ev, change_ev, release_ev;
  tgt_if #(FLOATING) tgt (drv_on);
  if (KIND == 0) begin : g_two_state_var
    bit [1:0] r = 2'b11;
    `FORCE_RELEASE(r)
    always @(change_ev) r = 2'b01;
  end else if (KIND == 1) begin : g_four_state_var
    logic [1:0] r = 2'b11;
    `FORCE_RELEASE(r)
    always @(change_ev) r = 2'b01;
  end else if (KIND == 2) begin : g_four_state_undriven
    logic [1:0] r;
    `FORCE_RELEASE(r)
  end else if (KIND == 3) begin : g_const_no_z
    `FORCE_RELEASE(2'b11)
  end else if (KIND == 4) begin : g_const_z
    `FORCE_RELEASE(2'bz1)
  end else if (KIND == 5) begin : g_tristate_net
    bit ten = 1'b0;
    wire [1:0] r;
    assign r = ten ? 2'b11 : 2'bzz;
    `FORCE_RELEASE(r)
    always @(change_ev) ten = 1'b1;
  end else if (KIND == 6) begin : g_tristate_sel
    bit ten = 1'b0;
    wire [3:0] r;
    assign r[3:2] = 2'b10;
    assign r[1:0] = ten ? 2'b11 : 2'bzz;
    `FORCE_RELEASE(r[2:1])
    always @(change_ev) ten = 1'b1;
  end else if (KIND == 7) begin : g_tristate_expr
    bit ten = 1'b0;
    wire [1:0] r;
    assign r = ten ? 2'b11 : 2'bzz;
    `FORCE_RELEASE(~r)
  end else if (KIND == 8) begin : g_tristate_and
    bit ten = 1'b0;
    bit [1:0] m = 2'b11;
    wire [1:0] r;
    assign r = ten ? 2'b11 : 2'bzz;
    `FORCE_RELEASE(r & m)
  end else if (KIND == 9) begin : g_xmod_4state
    src_if s ();
    `FORCE_RELEASE(s.l4)
    always @(change_ev) s.l4 = 2'b01;
  end else if (KIND == 10) begin : g_xmod_2state
    src_if s ();
    `FORCE_RELEASE(s.b2)
    always @(change_ev) s.b2 = 2'b01;
  end else if (KIND == 11) begin : g_xmod_net
    src_if s ();
    `FORCE_RELEASE(s.w4)
    always @(change_ev) s.l4 = 2'b01;
  end else if (KIND == 12) begin : g_xmod_tristate
    src_if s ();
    `FORCE_RELEASE(s.wt)
    always @(change_ev) s.ten = 1'b1;
  end else if (KIND == 13) begin : g_driven_concat
    logic [1:0] q = 2'b10;
    `FORCE_RELEASE({q[0], 1'b1})
    always @(change_ev) q = 2'b01;
  end else if (KIND == 14) begin : g_lognot_concat
    logic [1:0] q = 2'b10;
    `FORCE_RELEASE({1'b0, !q[1]})
    always @(change_ev) q = 2'b01;
  end else if (KIND == 15) begin : g_cell_net
    bit ten = 1'b0;
    wire [1:0] r;
    tri_drv c (r, ten);
    `FORCE_RELEASE(r)
    always @(change_ev) ten = 1'b1;
  end else if (KIND == 16) begin : g_tristate_cell_net
    bit ten = 1'b0;
    wire [1:0] r;
    assign r = ten ? 2'b10 : 2'bzz;
    const_drv c (r);
    `FORCE_RELEASE(r)
  end else if (KIND == 17) begin : g_forced_strength_src
    src_if s ();
    initial force s.fs = 2'bzz;
    `FORCE_RELEASE(s.fs)
    always @(change_ev) release s.fs;
  end else if (KIND == 18) begin : g_forced_var
    logic [1:0] r = 2'b11;
    initial force r = 2'b01;
    `FORCE_RELEASE(r)
    always @(change_ev) begin
      release r;
      r = 2'b10;
    end
  end else if (KIND == 19) begin : g_and_z_literal
    bit [1:0] m = 2'b11;
    `FORCE_RELEASE(m & 2'bz1)
    always @(change_ev) m = 2'b01;
  end else if (KIND == 20) begin : g_split_net
    bit lo = 1'b1;
    bit hi = 1'b1;
    wire [1:0] r;
    assign r[0] = lo;
    assign r[1] = hi;
    `FORCE_RELEASE(r)
    always @(change_ev) hi = 1'b0;
  end else if (KIND == 21) begin : g_pulled_net
    bit pen = 1'b0;
    tri0 [1:0] r;
    assign r = pen ? 2'b11 : 2'bzz;
    `FORCE_RELEASE(r)
    always @(change_ev) pen = 1'b1;
  end
  initial begin
    #1;
    `checkz(tgt.value, R0, 4'hf);
    ->force_ev;
    #1;
    `checkz(tgt.value, F, FC);
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, F, FC);
    ->change_ev;
    #1;
    `checkz(tgt.value, F2, F2C);
    ->release_ev;
    #1;
    `checkz(tgt.value, R1, 4'hf);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0, 4'hf);
  end
endmodule

// Direct and task forces and releases of the same nets
module m_mixed;
  bit drv_on = 1'b0;
  tgt_if #(0) a (drv_on);
  tgt_if #(1) f (drv_on);
  bit pen = 1'b0;
  tri0 [1:0] r;
  assign r = pen ? 2'b11 : 2'bzz;
  task force_a;
    force a.value = r;
  endtask
  task force_f;
    force f.value = 2'b11;
  endtask
  task release_a;
    release a.value;
  endtask
  task release_f;
    release f.value;
  endtask
  initial begin
    #1;
    force_a();
    force f.value = 2'bz1;
    #1;
    `checkz(a.value, 4'b0000, 4'hf);
    `checkz(f.value, 4'b1001, 4'hf);
    pen = 1'b1;
    drv_on = 1'b1;
    #1;
    `checkz(a.value, 4'b0011, 4'hf);
    `checkz(f.value, 4'b1001, 4'hf);
    release a.value;
    release_f();
    #1;
    `checkz(a.value, 4'b0001, 4'hf);
    `checkz(f.value, 4'b0000, 4'hf);
    force a.value = 2'bzz;
    force_f();
    #1;
    `checkz(a.value, 4'b1100, 4'hf);
    `checkz(f.value, 4'b0011, 4'hf);
    release_a();
    release f.value;
    drv_on = 1'b0;
    #1;
    `checkz(a.value, 4'b0010, 4'hf);
    `checkz(f.value, 4'b1100, 4'hf);
  end
endmodule

module t;
  m #(0, 0, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) two_state_var_direct_always ();
  m #(0, 1, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) two_state_var_direct_floating ();
  m #(0, 0, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) two_state_var_task_always ();
  m #(0, 1, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) two_state_var_task_floating ();
  m #(1, 0, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) four_state_var_direct_always ();
  m #(1, 1, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) four_state_var_direct_floating ();
  m #(1, 0, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) four_state_var_task_always ();
  m #(1, 1, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) four_state_var_task_floating ();
  m #(2, 0, 0, 4'b0000, 4'b1100, 4'b0000, 4'b1100) four_state_undriven_direct_always ();
  m #(2, 1, 0, 4'b0000, 4'b1100, 4'b0000, 4'b1100) four_state_undriven_direct_floating ();
  m #(2, 0, 1, 4'b0000, 4'b1100, 4'b0000, 4'b1100) four_state_undriven_task_always ();
  m #(2, 1, 1, 4'b0000, 4'b1100, 4'b0000, 4'b1100) four_state_undriven_task_floating ();
  m #(3, 0, 0, 4'b0011, 4'b1111, 4'b0011, 4'b1111) const_no_z_direct_always ();
  m #(3, 1, 0, 4'b0011, 4'b1111, 4'b0011, 4'b1111) const_no_z_direct_floating ();
  m #(3, 0, 1, 4'b0011, 4'b1111, 4'b0011, 4'b1111) const_no_z_task_always ();
  m #(3, 1, 1, 4'b0011, 4'b1111, 4'b0011, 4'b1111) const_no_z_task_floating ();
  m #(4, 0, 0, 4'b1001, 4'b1111, 4'b1001, 4'b1111) const_z_direct_always ();
  m #(4, 1, 0, 4'b1001, 4'b1111, 4'b1001, 4'b1111) const_z_direct_floating ();
  m #(5, 0, 0, 4'b1100, 4'b1111, 4'b0011, 4'b1111) tristate_net_direct_always ();
  m #(5, 1, 0, 4'b1100, 4'b1111, 4'b0011, 4'b1111) tristate_net_direct_floating ();
  m #(5, 0, 1, 4'b1100, 4'b1111, 4'b0011, 4'b1111) tristate_net_task_always ();
  m #(5, 1, 1, 4'b1100, 4'b1111, 4'b0011, 4'b1111) tristate_net_task_floating ();
  m #(6, 0, 0, 4'b0100, 4'b1111, 4'b0001, 4'b1111) tristate_sel_direct_always ();
  m #(6, 1, 0, 4'b0100, 4'b1111, 4'b0001, 4'b1111) tristate_sel_direct_floating ();
  m #(6, 0, 1, 4'b0100, 4'b1111, 4'b0001, 4'b1111) tristate_sel_task_always ();
  m #(6, 1, 1, 4'b0100, 4'b1111, 4'b0001, 4'b1111) tristate_sel_task_floating ();
  m #(7, 0, 0, 4'b0000, 4'b1100, 4'b0000, 4'b1100) tristate_expr_direct_always ();
  m #(7, 1, 0, 4'b0000, 4'b1100, 4'b0000, 4'b1100) tristate_expr_direct_floating ();
  m #(7, 0, 1, 4'b0000, 4'b1100, 4'b0000, 4'b1100) tristate_expr_task_always ();
  m #(7, 1, 1, 4'b0000, 4'b1100, 4'b0000, 4'b1100) tristate_expr_task_floating ();
  m #(8, 0, 0, 4'b0000, 4'b1100, 4'b0000, 4'b1100) tristate_and_direct_always ();
  m #(8, 1, 0, 4'b0000, 4'b1100, 4'b0000, 4'b1100) tristate_and_direct_floating ();
  m #(8, 0, 1, 4'b0000, 4'b1100, 4'b0000, 4'b1100) tristate_and_task_always ();
  m #(8, 1, 1, 4'b0000, 4'b1100, 4'b0000, 4'b1100) tristate_and_task_floating ();
  m #(9, 0, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_4state_direct_always ();
  m #(9, 1, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_4state_direct_floating ();
  m #(9, 0, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_4state_task_always ();
  m #(9, 1, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_4state_task_floating ();
  m #(10, 0, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_2state_direct_always ();
  m #(10, 1, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_2state_direct_floating ();
  m #(10, 0, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_2state_task_always ();
  m #(10, 1, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_2state_task_floating ();
  m #(11, 0, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_net_direct_always ();
  m #(11, 1, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_net_direct_floating ();
  m #(11, 0, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_net_task_always ();
  m #(11, 1, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) xmod_net_task_floating ();
  m #(12, 0, 0, 4'b1100, 4'b1111, 4'b0010, 4'b1111) xmod_tristate_direct_always ();
  m #(12, 1, 0, 4'b1100, 4'b1111, 4'b0010, 4'b1111) xmod_tristate_direct_floating ();
  m #(12, 0, 1, 4'b1100, 4'b1111, 4'b0010, 4'b1111) xmod_tristate_task_always ();
  m #(12, 1, 1, 4'b1100, 4'b1111, 4'b0010, 4'b1111) xmod_tristate_task_floating ();
  m #(13, 0, 0, 4'b0001, 4'b1111, 4'b0011, 4'b1111) driven_concat_direct_always ();
  m #(13, 1, 0, 4'b0001, 4'b1111, 4'b0011, 4'b1111) driven_concat_direct_floating ();
  m #(13, 0, 1, 4'b0001, 4'b1111, 4'b0011, 4'b1111) driven_concat_task_always ();
  m #(13, 1, 1, 4'b0001, 4'b1111, 4'b0011, 4'b1111) driven_concat_task_floating ();
  m #(14, 0, 0, 4'b0000, 4'b1111, 4'b0001, 4'b1111) lognot_concat_direct_always ();
  m #(14, 1, 0, 4'b0000, 4'b1111, 4'b0001, 4'b1111) lognot_concat_direct_floating ();
  m #(14, 0, 1, 4'b0000, 4'b1111, 4'b0001, 4'b1111) lognot_concat_task_always ();
  m #(14, 1, 1, 4'b0000, 4'b1111, 4'b0001, 4'b1111) lognot_concat_task_floating ();
  m #(15, 0, 0, 4'b1100, 4'b1111, 4'b0011, 4'b1111) cell_net_direct_always ();
  m #(15, 1, 0, 4'b1100, 4'b1111, 4'b0011, 4'b1111) cell_net_direct_floating ();
  m #(15, 0, 1, 4'b1100, 4'b1111, 4'b0011, 4'b1111) cell_net_task_always ();
  m #(15, 1, 1, 4'b1100, 4'b1111, 4'b0011, 4'b1111) cell_net_task_floating ();
  m #(16, 0, 0, 4'b0010, 4'b1111, 4'b0010, 4'b1111) tristate_cell_net_direct_always ();
  m #(16, 1, 0, 4'b0010, 4'b1111, 4'b0010, 4'b1111) tristate_cell_net_direct_floating ();
  m #(16, 0, 1, 4'b0010, 4'b1111, 4'b0010, 4'b1111) tristate_cell_net_task_always ();
  m #(16, 1, 1, 4'b0010, 4'b1111, 4'b0010, 4'b1111) tristate_cell_net_task_floating ();
  m #(17, 0, 0, 4'b1100, 4'b1111, 4'b0010, 4'b1111) forced_strength_src_direct_always ();
  m #(17, 1, 0, 4'b1100, 4'b1111, 4'b0010, 4'b1111) forced_strength_src_direct_floating ();
  m #(17, 0, 1, 4'b1100, 4'b1111, 4'b0010, 4'b1111) forced_strength_src_task_always ();
  m #(17, 1, 1, 4'b1100, 4'b1111, 4'b0010, 4'b1111) forced_strength_src_task_floating ();
  m #(18, 0, 0, 4'b0001, 4'b1111, 4'b0010, 4'b1111) forced_var_direct_always ();
  m #(18, 1, 0, 4'b0001, 4'b1111, 4'b0010, 4'b1111) forced_var_direct_floating ();
  m #(18, 0, 1, 4'b0001, 4'b1111, 4'b0010, 4'b1111) forced_var_task_always ();
  m #(18, 1, 1, 4'b0001, 4'b1111, 4'b0010, 4'b1111) forced_var_task_floating ();
  m #(19, 0, 1, 4'b0001, 4'b1101, 4'b0001, 4'b1111) and_z_literal_task_always ();
  m #(19, 1, 1, 4'b0001, 4'b1101, 4'b0001, 4'b1111) and_z_literal_task_floating ();
  m #(20, 0, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) split_net_direct_always ();
  m #(20, 1, 0, 4'b0011, 4'b1111, 4'b0001, 4'b1111) split_net_direct_floating ();
  m #(20, 0, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) split_net_task_always ();
  m #(20, 1, 1, 4'b0011, 4'b1111, 4'b0001, 4'b1111) split_net_task_floating ();
  m #(21, 0, 0, 4'b0000, 4'b1111, 4'b0011, 4'b1111) pulled_net_direct_always ();
  m #(21, 1, 0, 4'b0000, 4'b1111, 4'b0011, 4'b1111) pulled_net_direct_floating ();
  m #(21, 0, 1, 4'b0000, 4'b1111, 4'b0011, 4'b1111) pulled_net_task_always ();
  m #(21, 1, 1, 4'b0000, 4'b1111, 4'b0011, 4'b1111) pulled_net_task_floating ();
  m_mixed mixed ();
  initial begin
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
