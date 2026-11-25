// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc;
  logic [14:0] q = 0;
endinterface

interface extra #(
    parameter int K = 0
);
  logic [14:0] z = 0;
endinterface

// One shared helper called by many methods, mutually recursive methods, and a diamond of calls
interface ifc4;
  logic [14:0] p = 0;
  logic [14:0] r = 0;
  logic [14:0] s = 0;
  logic [14:0] b = 0;

  function automatic logic [14:0] common();
    // verilator no_inline_task
    return p;
  endfunction
  `define IFC4_METHOD(k) \
  function automatic logic [14:0] f``k(); \
    return common() ^ 15'(k); \
  endfunction
  `IFC4_METHOD(0)
  `IFC4_METHOD(1)
  `IFC4_METHOD(2)
  `IFC4_METHOD(3)
  `IFC4_METHOD(4)
  `IFC4_METHOD(5)
  `IFC4_METHOD(6)
  `IFC4_METHOD(7)
  `IFC4_METHOD(8)
  `IFC4_METHOD(9)
  `IFC4_METHOD(10)
  `IFC4_METHOD(11)
  `IFC4_METHOD(12)
  `IFC4_METHOD(13)
  `IFC4_METHOD(14)
  `IFC4_METHOD(15)

  function automatic logic [14:0] even(int n);
    // verilator no_inline_task
    return n == 0 ? r : odd(n - 1);
  endfunction
  function automatic logic [14:0] odd(int n);
    // verilator no_inline_task
    return n == 0 ? s : even(n - 1);
  endfunction

  function automatic logic [14:0] base();
    // verilator no_inline_task
    return b;
  endfunction
  function automatic logic [14:0] left();
    // verilator no_inline_task
    return base() + 15'd1;
  endfunction
  function automatic logic [14:0] right();
    // verilator no_inline_task
    return base() ^ 15'd1;
  endfunction
  function automatic logic [14:0] top();
    // verilator no_inline_task
    return left() ^ right();
  endfunction
endinterface

module t (
    input clk,
    output logic [14:0] sum,
    output logic [14:0] sum2,
    output logic [14:0] sum3,
    output logic [14:0] sum4
);
  localparam int N = 64;
  logic [N-1:0] clks = 0;
  logic [14:0] d = 0;
  always @(posedge clk) begin
    clks <= clks + 1;
    d <= d + 15'd3;
  end

  // Readers through virtual interfaces in distinct clock domains, each of which may read the
  // member in every instance. Their ordering edges stay linear in readers and instances.
  logic [14:0] o[N];
  for (genvar k = 0; k < N; ++k) begin : g
    ifc b ();
    virtual ifc v = b;
    always @(posedge clk) b.q <= d ^ 15'(k);
    always @(posedge clks[k]) o[k] <= v.q + o[k];
  end
  always_comb begin
    sum = 0;
    for (int k = 0; k < N; ++k) sum ^= o[k];
  end

  // Readers in one clock domain, each through its own function, all reading the same members.
  // They share one barrier.
  logic [14:0] o2[N];
  for (genvar k = 0; k < N; ++k) begin : g2
    function automatic logic [14:0] rd(virtual ifc h);
      // verilator no_inline_task
      return h.q;
    endfunction
    always @(posedge clk) o2[k] <= rd(g[k].v) + o2[k];
  end
  always_comb begin
    sum2 = 0;
    for (int k = 0; k < N; ++k) sum2 ^= o2[k];
  end

  // Readers each through its own function reading the same member, and a member of its own.
  // Each member has one barrier.
  logic [14:0] o3[N];
  for (genvar k = 0; k < N; ++k) begin : g3
    extra #(.K(k)) e ();
    virtual extra #(.K(k)) w = e;
    always @(posedge clk) e.z <= e.z + 15'(k + 1);
    function automatic logic [14:0] rd(virtual ifc h, virtual extra #(.K(k)) j);
      // verilator no_inline_task
      return h.q ^ j.z;
    endfunction
    always @(posedge clk) o3[k] <= rd(g[k].v, w) + o3[k];
  end
  always_comb begin
    sum3 = 0;
    for (int k = 0; k < N; ++k) sum3 ^= o3[k];
  end

  // Readers each through a different method calling the shared helper, and through the
  // recursive and diamond methods. Each member has one barrier, whatever the calls.
  logic [14:0] o4[16];
  `define IFC4_READER(k) \
  ifc4 i4_``k (); \
  virtual ifc4 v4_``k = i4_``k; \
  always @(posedge clk) begin \
    i4_``k.p <= d ^ 15'(k); \
    i4_``k.r <= d + 15'(k); \
    i4_``k.s <= d - 15'(k); \
    i4_``k.b <= d ^ 15'(k * 3); \
  end \
  always @(posedge clk) o4[k] <= v4_``k.f``k() ^ v4_``k.even(k % 3) ^ v4_``k.top() + o4[k];
  `IFC4_READER(0)
  `IFC4_READER(1)
  `IFC4_READER(2)
  `IFC4_READER(3)
  `IFC4_READER(4)
  `IFC4_READER(5)
  `IFC4_READER(6)
  `IFC4_READER(7)
  `IFC4_READER(8)
  `IFC4_READER(9)
  `IFC4_READER(10)
  `IFC4_READER(11)
  `IFC4_READER(12)
  `IFC4_READER(13)
  `IFC4_READER(14)
  `IFC4_READER(15)
  always_comb begin
    sum4 = 0;
    for (int k = 0; k < 16; ++k) sum4 ^= o4[k];
  end
endmodule
