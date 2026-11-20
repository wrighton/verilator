// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// Check the z bits and the one bits of a 2-bit net
`define checkz(gotv,expv) `checkh({gotv[1] === 1'bz, gotv[0] === 1'bz, gotv[1] === 1'b1, gotv[0] === 1'b1}, expv)
// verilog_format: on

// Each force value kind forced on interface strength nets that are always driven (weak plus
// a strong driver) or floating, directly and from a task: force, change the net's driver and
// the value, then release (IEEE 1800-2023 10.6.2).

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

interface src_if;
  logic [1:0] l4 = 2'b11;
  bit [1:0] b2 = 2'b11;
  wire [1:0] w4 = l4;
  bit ten = 1'b0;
  wire [1:0] wt;
  assign (weak0, weak1) wt = ten ? 2'b10 : 2'bzz;
endinterface

// r
module m_two_state_var #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  bit [1:0] r = 2'b11;
  task force_tgt;
    force tgt.value = r;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    r = 2'b01;
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// r
module m_four_state_var #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  logic [1:0] r = 2'b11;
  task force_tgt;
    force tgt.value = r;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    r = 2'b01;
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// r
module m_four_state_undriven #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  logic [1:0] r;
  task force_tgt;
    force tgt.value = r;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r;
    #1;
    `checkh(tgt.value[1] === 1'bz || tgt.value[0] === 1'bz, 1'b0);
    drv_on = 1'b1;
    #1;
    `checkh(tgt.value[1] === 1'bz || tgt.value[0] === 1'bz, 1'b0);
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// 2'b11
module m_const_no_z #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  task force_tgt;
    force tgt.value = 2'b11;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = 2'b11;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// 2'bz1
module m_const_z #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  initial begin
    #1;
    `checkz(tgt.value, R0);
    force tgt.value = 2'bz1;
    #1;
    `checkz(tgt.value, 4'b1001);  // z1
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b1001);  // z1
    release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// r
module m_tristate_net #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  bit ten = 1'b0;
  wire [1:0] r;
  assign r = ten ? 2'b11 : 2'bzz;
  task force_tgt;
    force tgt.value = r;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r;
    #1;
    `checkz(tgt.value, 4'b1100);  // zz
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b1100);  // zz
    ten = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// r[2:1]
module m_tristate_sel #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  bit ten = 1'b0;
  wire [3:0] r;
  assign r[3:2] = 2'b10;
  assign r[1:0] = ten ? 2'b11 : 2'bzz;
  task force_tgt;
    force tgt.value = r[2:1];
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r[2:1];
    #1;
    `checkz(tgt.value, 4'b0100);  // 0z
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0100);  // 0z
    ten = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// ~r
module m_tristate_expr #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  bit ten = 1'b0;
  wire [1:0] r;
  assign r = ten ? 2'b11 : 2'bzz;
  task force_tgt;
    force tgt.value = ~r;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = ~r;
    #1;
    `checkh(tgt.value[1] === 1'bz || tgt.value[0] === 1'bz, 1'b0);
    drv_on = 1'b1;
    #1;
    `checkh(tgt.value[1] === 1'bz || tgt.value[0] === 1'bz, 1'b0);
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// r & m
module m_tristate_and #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  bit ten = 1'b0;
  bit [1:0] m = 2'b11;
  wire [1:0] r;
  assign r = ten ? 2'b11 : 2'bzz;
  task force_tgt;
    force tgt.value = r & m;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r & m;
    #1;
    `checkh(tgt.value[1] === 1'bz || tgt.value[0] === 1'bz, 1'b0);
    drv_on = 1'b1;
    #1;
    `checkh(tgt.value[1] === 1'bz || tgt.value[0] === 1'bz, 1'b0);
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// s.l4
module m_xmod_4state #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  src_if s ();
  task force_tgt;
    force tgt.value = s.l4;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = s.l4;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    s.l4 = 2'b01;
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// s.b2
module m_xmod_2state #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  src_if s ();
  task force_tgt;
    force tgt.value = s.b2;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = s.b2;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    s.b2 = 2'b01;
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// s.w4
module m_xmod_net #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  src_if s ();
  task force_tgt;
    force tgt.value = s.w4;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = s.w4;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    s.l4 = 2'b01;
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// s.wt
module m_xmod_tristate #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  src_if s ();
  task force_tgt;
    force tgt.value = s.wt;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = s.wt;
    #1;
    `checkz(tgt.value, 4'b1100);  // zz
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b1100);  // zz
    s.ten = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0010);  // 10
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// {q[0], 1'b1}
module m_driven_concat #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  logic [1:0] q = 2'b10;
  task force_tgt;
    force tgt.value = {q[0], 1'b1};
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = {q[0], 1'b1};
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    q = 2'b01;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// {1'b0, !q[1]}
module m_lognot_concat #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  logic [1:0] q = 2'b10;
  task force_tgt;
    force tgt.value = {1'b0, !q[1]};
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = {1'b0, !q[1]};
    #1;
    `checkz(tgt.value, 4'b0000);  // 00
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0000);  // 00
    q = 2'b01;
    #1;
    `checkz(tgt.value, 4'b0001);  // 01
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// r
module m_cell_net #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  bit ten = 1'b0;
  wire [1:0] r;
  tri_drv c (r, ten);
  task force_tgt;
    force tgt.value = r;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r;
    #1;
    `checkz(tgt.value, 4'b1100);  // zz
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b1100);  // zz
    ten = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// r
module m_tristate_cell_net #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  bit ten = 1'b0;
  wire [1:0] r;
  assign r = ten ? 2'b10 : 2'bzz;
  const_drv c (r);
  task force_tgt;
    force tgt.value = r;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r;
    #1;
    `checkz(tgt.value, 4'b0010);  // 10
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0010);  // 10
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// r
module m_pulled_net #(
    parameter bit FLOATING = 0,
    parameter bit TASK = 0
);
  localparam bit [3:0] R0 = FLOATING ? 4'b1100 : 4'b0010;
  localparam bit [3:0] R1 = FLOATING ? 4'b0000 : 4'b0001;
  bit drv_on = 1'b0;
  tgt_if #(FLOATING) tgt (drv_on);
  bit pen = 1'b0;
  tri0 [1:0] r;
  assign r = pen ? 2'b11 : 2'bzz;
  task force_tgt;
    force tgt.value = r;
  endtask
  task release_tgt;
    release tgt.value;
  endtask
  initial begin
    #1;
    `checkz(tgt.value, R0);
    if (TASK) force_tgt();
    else force tgt.value = r;
    #1;
    `checkz(tgt.value, 4'b0000);  // 00
    drv_on = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0000);  // 00
    pen = 1'b1;
    #1;
    `checkz(tgt.value, 4'b0011);  // 11
    if (TASK) release_tgt();
    else release tgt.value;
    #1;
    `checkz(tgt.value, R1);
    drv_on = 1'b0;
    #1;
    `checkz(tgt.value, R0);
  end
endmodule

// Direct and task forces and releases on the same nets
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
    `checkz(a.value, 4'b0000);  // 00
    `checkz(f.value, 4'b1001);  // z1
    pen = 1'b1;
    drv_on = 1'b1;
    #1;
    `checkz(a.value, 4'b0011);  // 11
    `checkz(f.value, 4'b1001);  // z1
    release a.value;
    release_f();
    #1;
    `checkz(a.value, 4'b0001);  // 01
    `checkz(f.value, 4'b0000);  // 00
    force a.value = 2'bzz;
    force_f();
    #1;
    `checkz(a.value, 4'b1100);  // zz
    `checkz(f.value, 4'b0011);  // 11
    release_a();
    release f.value;
    drv_on = 1'b0;
    #1;
    `checkz(a.value, 4'b0010);  // 10
    `checkz(f.value, 4'b1100);  // zz
  end
endmodule

module t;
  m_two_state_var #(0, 0) two_state_var_direct_always ();
  m_two_state_var #(1, 0) two_state_var_direct_floating ();
  m_two_state_var #(0, 1) two_state_var_task_always ();
  m_two_state_var #(1, 1) two_state_var_task_floating ();
  m_four_state_var #(0, 0) four_state_var_direct_always ();
  m_four_state_var #(1, 0) four_state_var_direct_floating ();
  m_four_state_var #(0, 1) four_state_var_task_always ();
  m_four_state_var #(1, 1) four_state_var_task_floating ();
  m_four_state_undriven #(0, 0) four_state_undriven_direct_always ();
  m_four_state_undriven #(1, 0) four_state_undriven_direct_floating ();
  m_four_state_undriven #(0, 1) four_state_undriven_task_always ();
  m_four_state_undriven #(1, 1) four_state_undriven_task_floating ();
  m_const_no_z #(0, 0) const_no_z_direct_always ();
  m_const_no_z #(1, 0) const_no_z_direct_floating ();
  m_const_no_z #(0, 1) const_no_z_task_always ();
  m_const_no_z #(1, 1) const_no_z_task_floating ();
  m_const_z #(0, 0) const_z_direct_always ();
  m_const_z #(1, 0) const_z_direct_floating ();
  m_tristate_net #(0, 0) tristate_net_direct_always ();
  m_tristate_net #(1, 0) tristate_net_direct_floating ();
  m_tristate_net #(0, 1) tristate_net_task_always ();
  m_tristate_net #(1, 1) tristate_net_task_floating ();
  m_tristate_sel #(0, 0) tristate_sel_direct_always ();
  m_tristate_sel #(1, 0) tristate_sel_direct_floating ();
  m_tristate_sel #(0, 1) tristate_sel_task_always ();
  m_tristate_sel #(1, 1) tristate_sel_task_floating ();
  m_tristate_expr #(0, 0) tristate_expr_direct_always ();
  m_tristate_expr #(1, 0) tristate_expr_direct_floating ();
  m_tristate_expr #(0, 1) tristate_expr_task_always ();
  m_tristate_expr #(1, 1) tristate_expr_task_floating ();
  m_tristate_and #(0, 0) tristate_and_direct_always ();
  m_tristate_and #(1, 0) tristate_and_direct_floating ();
  m_tristate_and #(0, 1) tristate_and_task_always ();
  m_tristate_and #(1, 1) tristate_and_task_floating ();
  m_xmod_4state #(0, 0) xmod_4state_direct_always ();
  m_xmod_4state #(1, 0) xmod_4state_direct_floating ();
  m_xmod_4state #(0, 1) xmod_4state_task_always ();
  m_xmod_4state #(1, 1) xmod_4state_task_floating ();
  m_xmod_2state #(0, 0) xmod_2state_direct_always ();
  m_xmod_2state #(1, 0) xmod_2state_direct_floating ();
  m_xmod_2state #(0, 1) xmod_2state_task_always ();
  m_xmod_2state #(1, 1) xmod_2state_task_floating ();
  m_xmod_net #(0, 0) xmod_net_direct_always ();
  m_xmod_net #(1, 0) xmod_net_direct_floating ();
  m_xmod_net #(0, 1) xmod_net_task_always ();
  m_xmod_net #(1, 1) xmod_net_task_floating ();
  m_xmod_tristate #(0, 0) xmod_tristate_direct_always ();
  m_xmod_tristate #(1, 0) xmod_tristate_direct_floating ();
  m_xmod_tristate #(0, 1) xmod_tristate_task_always ();
  m_xmod_tristate #(1, 1) xmod_tristate_task_floating ();
  m_driven_concat #(0, 0) driven_concat_direct_always ();
  m_driven_concat #(1, 0) driven_concat_direct_floating ();
  m_driven_concat #(0, 1) driven_concat_task_always ();
  m_driven_concat #(1, 1) driven_concat_task_floating ();
  m_lognot_concat #(0, 0) lognot_concat_direct_always ();
  m_lognot_concat #(1, 0) lognot_concat_direct_floating ();
  m_lognot_concat #(0, 1) lognot_concat_task_always ();
  m_lognot_concat #(1, 1) lognot_concat_task_floating ();
  m_cell_net #(0, 0) cell_net_direct_always ();
  m_cell_net #(1, 0) cell_net_direct_floating ();
  m_cell_net #(0, 1) cell_net_task_always ();
  m_cell_net #(1, 1) cell_net_task_floating ();
  m_tristate_cell_net #(0, 0) tristate_cell_net_direct_always ();
  m_tristate_cell_net #(1, 0) tristate_cell_net_direct_floating ();
  m_tristate_cell_net #(0, 1) tristate_cell_net_task_always ();
  m_tristate_cell_net #(1, 1) tristate_cell_net_task_floating ();
  m_pulled_net #(0, 0) pulled_net_direct_always ();
  m_pulled_net #(1, 0) pulled_net_direct_floating ();
  m_pulled_net #(0, 1) pulled_net_task_always ();
  m_pulled_net #(1, 1) pulled_net_task_floating ();
  m_mixed mixed ();
  initial begin
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
