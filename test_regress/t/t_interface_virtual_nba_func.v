// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface src;
  logic [6:0] y = 0;
  logic [6:0] z = 0;

  function automatic logic [6:0] get_y();
    // verilator no_inline_task
    return y;
  endfunction
endinterface

interface ifc;
  logic [6:0] q = 0;
  logic [6:0] u = 0;
  logic [6:0] v = 0;
  logic [6:0] w = 0;
  logic [6:0] x = 0;

  function automatic logic [6:0] get_v();
    // verilator no_inline_task
    return v;
  endfunction
  // Reads two members, each only here: one directly, one in a function it calls
  function automatic logic [13:0] read_uv();
    // verilator no_inline_task
    return {u, get_v()};
  endfunction

  // Reads through a virtual interface argument, directly and in a method called through it
  function automatic logic [6:0] fetch_z(virtual src h);
    return h.z;
  endfunction
  function automatic logic [6:0] fetch_y(virtual src h);
    return h.get_y();
  endfunction
endinterface

// A class holding a virtual interface, as for a driver or monitor object
class Box;
  virtual ifc vi;
  function new(virtual ifc v);
    vi = v;
  endfunction
  virtual function logic [6:0] get();
    return vi.w;
  endfunction
  virtual function logic [6:0] other();
    return vi.w;
  endfunction
  function logic [6:0] get2();
    return other() ^ 7'h5a;
  endfunction
endclass

// Overrides 'other' to read another member, read through a virtual interface only here
class Box2 extends Box;
  function new(virtual ifc v);
    super.new(v);
  endfunction
  virtual function logic [6:0] other();
    return vi.x;
  endfunction
endclass

module t (
    input clk
);
  int cyc = 0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  function automatic logic [6:0] read_q(virtual ifc h);
    // verilator no_inline_task
    return h.q;
  endfunction

  function automatic logic [6:0] read_q_twice(virtual ifc h);
    // verilator no_inline_task
    return read_q(h) ^ read_q(h) ^ read_q(h);
  endfunction

  // A read through a virtual interface in a function called on the edge of a nonblocking
  // assignment to the member sees the value before the assignment (IEEE 1800-2023 4.9.4)
  ifc i ();
  virtual ifc vi = i;
  logic [6:0] q_exp = 0;
  logic [13:0] uv_exp = 0;
  always @(posedge clk) begin
    i.q <= crc[6:0];
    i.u <= crc[48:42];
    i.v <= crc[55:49];
    q_exp <= crc[6:0];
    uv_exp <= {crc[48:42], crc[55:49]};
    if (cyc > 1) begin
      `checkh(read_q(vi), q_exp);
      `checkh(read_q_twice(vi), q_exp);
      `checkh(vi.read_uv(), uv_exp);
    end
  end

  // Also when written and read in separate processes doing unrelated work
  ifc i2 ();
  virtual ifc vi2 = i2;
  logic [63:0] wa = 0;
  always @(posedge clk) begin
    i2.q <= crc[13:7];
    for (int k = 0; k < 64; ++k) wa[k] <= ^(crc & (64'h1 << k)) ^ wa[(k+7)%64];
  end
  logic [6:0] q2_exp = 0;
  logic [63:0] ra = 0;
  always @(posedge clk) begin
    for (int k = 0; k < 64; ++k) ra[k] <= ^(crc & (64'h3 << k)) ^ ra[(k+5)%64];
    q2_exp <= crc[13:7];
    if (cyc > 1) `checkh(read_q(vi2), q2_exp);
    if (cyc == 98 && wa == ra) `stop;
  end

  // Also in methods called through a virtual interface, reading through a virtual interface
  // argument, including in a method they call through it
  src s ();
  virtual src vs = s;
  logic [6:0] y_exp = 0;
  logic [6:0] z_exp = 0;
  always @(posedge clk) begin
    s.y <= crc[20:14];
    s.z <= crc[27:21];
    y_exp <= crc[20:14];
    z_exp <= crc[27:21];
    if (cyc > 1) begin
      `checkh(vi.fetch_y(vs), y_exp);
      `checkh(vi.fetch_z(vs), z_exp);
    end
  end

  // Also with each of two members read in a separate process doing unrelated work, so each
  // read must be ordered before the update of its member
  src s2 ();
  virtual src vs2 = s2;
  logic [63:0] wb = 0;
  always @(posedge clk) begin
    s2.y <= crc[34:28];
    s2.z <= crc[41:35];
    for (int k = 0; k < 64; ++k) wb[k] <= ^(crc & (64'h5 << k)) ^ wb[(k+3)%64];
  end
  logic [6:0] y2_exp = 0;
  logic [6:0] z2_exp = 0;
  logic [63:0] rb = 0;
  always @(posedge clk) begin
    for (int k = 0; k < 64; ++k) rb[k] <= ^(crc & (64'h9 << k)) ^ rb[(k+11)%64];
    y2_exp <= crc[34:28];
    z2_exp <= crc[41:35];
    if (cyc > 1) `checkh({vi.fetch_y(vs2), vi.fetch_z(vs2)}, {y2_exp, z2_exp});
    if (cyc == 98 && wb == rb) `stop;
  end

  // Also in methods of a class holding a virtual interface, which are the only reads of the
  // members through a virtual interface, including in an override of a method they call
  ifc i3 ();
  Box box;
  Box box2;
  Box2 box2_obj;
  initial begin
    box = new(i3);
    box2_obj = new(i3);
    box2 = box2_obj;
  end
  logic [6:0] w_exp = 0;
  logic [6:0] x_exp = 0;
  always @(posedge clk) begin
    i3.w <= crc[6:0];
    i3.x <= crc[13:7];
    w_exp <= crc[6:0];
    x_exp <= crc[13:7];
    if (cyc > 1) begin
      `checkh(box.get(), w_exp);
      `checkh(box2.get2(), x_exp ^ 7'h5a);
    end
  end
endmodule
