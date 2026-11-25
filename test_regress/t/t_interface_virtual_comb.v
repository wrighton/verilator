// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface ifc;
  logic [6:0] q = 0;
  logic [14:0] w;
  logic [10:0] r;
  logic [30:0] acc;

  function automatic logic [6:0] peek();
    // verilator no_inline_task
    return q;
  endfunction

  function automatic logic [14:0] scaled();
    return 15'(peek()) * 3 + w;
  endfunction

  task automatic bump(input logic [30:0] d);
    acc <= acc + d;
  endtask
endinterface

class Holder;
  virtual ifc v;
endclass

interface tifc;
  logic [6:0] q = 0;

  task automatic get(output logic [6:0] result);
    // verilator no_inline_task
    result = q;
  endtask
endinterface

module t (
    input clk
);
  int cyc = 0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;

  ifc i1 ();
  ifc i2 ();

  // Written directly, not through the virtual interface
  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    i1.q <= crc[6:0];
    i1.w <= crc[30:16];
    i2.q <= crc[38:32];
    i2.w <= crc[62:48];
    i1.r <= crc[50:40];
    i2.r <= crc[61:51];
  end

  // Selects the other instance every 16 cycles
  virtual ifc vi = i1;
  logic sel = 0;
  always @(cyc[4]) begin
    sel = cyc[4];
    if (sel) vi = i2;
    else vi = i1;
  end
  wire [6:0] q_exp = sel ? i2.q : i1.q;
  wire [14:0] w_exp = sel ? i2.w : i1.w;
  wire [10:0] r_exp = sel ? i2.r : i1.r;

  // An always_comb is sensitive to the variables read through the virtual
  // interface, also by the functions it calls (IEEE 1800-2023 9.2.2.2.1)
  logic [6:0] peeked;
  always_comb peeked = vi.peek();

  logic [14:0] scaled;
  always_comb scaled = vi.scaled();

  logic [2:0] ones;
  always_comb begin
    ones = 0;
    for (int k = 0; k < 7; ++k) if (vi.q[k]) ones = ones + 1;
  end

  // Also through arrays of virtual interfaces
  virtual ifc vis[2:1];
  virtual ifc vid[];
  virtual ifc viq[$];
  virtual ifc via[int];
  initial begin
    vis[1] = i1;
    vis[2] = i2;
    vid = new[2];
    vid[0] = i1;
    vid[1] = i2;
    viq.push_back(i1);
    viq.push_back(i2);
    via[-1] = i1;
    via[5] = i2;
  end
  logic [6:0] arr_q[4];
  always_comb begin
    arr_q = '{default: 0};
    if (vis[2] != null) arr_q[0] = vis[sel ? 2 : 1].q;
    if (vid.size() == 2) arr_q[1] = vid[int'(sel)].q;
    if (viq.size() == 2) arr_q[2] = viq[int'(sel)].q;
    if (via.exists(5)) arr_q[3] = via[sel ? 5 : -1].q;
  end
  logic [6:0] arr_sum;
  always_comb begin
    arr_sum = 0;
    for (int k = 1; k <= 2; ++k) if (vis[k] != null) arr_sum += vis[k].q;
  end

  // Also through a virtual interface held by a class object
  Holder h = new;
  initial h.v = i2;
  logic [6:0] held_q;
  always_comb held_q = h.v != null ? h.v.q : 0;

  // Also through a function that is not a method of the interface
  function automatic logic [10:0] get_r(input virtual ifc v);
    // verilator no_inline_task
    return v != null ? v.r : 0;
  endfunction
  logic [10:0] wrapped[3];
  always_comb begin
    wrapped[0] = get_r(vi);
    wrapped[1] = get_r(vis[sel ? 2 : 1]);
    wrapped[2] = get_r(h.v);
  end

  // The body of a task called through the virtual interface does not add to the
  // sensitivity of the always_comb, so this is evaluated only at time zero
  tifc ti ();
  virtual tifc tvi = ti;
  always @(posedge clk) ti.q <= crc[46:40];
  logic [6:0] tasked;
  always_comb tvi.get(tasked);

  // Writes through a method of the virtual interface trigger direct readers
  initial i1.acc = 0;
  always @(posedge clk) vi.bump(31'(crc[20:0]));
  logic [30:0] acc1;
  always_comb acc1 = i1.acc;
  logic [30:0] acc1_exp = 0;

  always @(posedge clk) begin
    if (cyc > 2) begin
      `checkh(peeked, q_exp);
      `checkh(scaled, 15'(q_exp) * 3 + w_exp);
      `checkh(ones, 3'($countones(q_exp)));
      for (int k = 0; k < 4; ++k) `checkh(arr_q[k], q_exp);
      `checkh(arr_sum, i1.q + i2.q);
      `checkh(held_q, i2.q);
      `checkh(wrapped[0], r_exp);
      `checkh(wrapped[1], r_exp);
      `checkh(wrapped[2], i2.r);
      `checkh(tasked, 7'h0);
      `checkh(acc1, acc1_exp);
    end
    if (!sel) acc1_exp <= acc1_exp + 31'(crc[20:0]);
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
