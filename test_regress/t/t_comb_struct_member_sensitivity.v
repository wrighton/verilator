// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A process reading a member of a packed structure another process writes is sensitive to it
// (IEEE 1800-2023 9.2.2.2.1), also after writing another member of the structure

typedef struct packed {
  logic [299:0] data;
  logic [7:0] par;
} wide_t;

typedef struct packed {
  logic [256:0] data;
  logic [10:0] fold;
} odd_t;

typedef struct packed {
  logic [4:0] f;
  logic [2:0] g;
} edge_t;

typedef struct packed {
  logic [3:0] a;
  logic [3:0] b;
  logic [3:0] x;
} narrow_t;

module t (
    input clk
);
  int cyc = 0;
  logic [299:0] q = '0;
  logic [3:0] qa = '0;
  logic [3:0] qb = '0;
  logic [3:0] k = 4'd2;  // A variable index

  function automatic logic [7:0] parity(logic [299:0] d);
    parity = '1;
    for (int i = 0; i < $bits(d); i++) parity[i%8] ^= d[i];
  endfunction

  function automatic logic [3:0] mfold(logic [3:0] a, logic [3:0] b);
    mfold = '0;
    for (int i = 1; i < 100; i++) mfold = mfold ^ (a + 4'(i)) ^ b;
  endfunction

  function automatic logic [10:0] fold(logic [256:0] d);
    fold = '0;
    for (int i = 0; i < $bits(d); i++) fold[i%11] ^= d[i];
  endfunction

  // Test: a member computed in a loop not unrolled, from a member another always_comb writes
  wide_t w;
  always_comb begin
    w.par = '1;
    for (int i = 0; i < $bits(w.data); i++) w.par[i%8] ^= w.data[i];
  end
  always_comb w.data = q;

  // Test: the same with always @*
  wide_t s;
  always @* begin
    s.par = '1;
    for (int i = 0; i < $bits(s.data); i++) s.par[i%8] ^= s.data[i];
  end
  always @* s.data = ~q;

  // Test: a member indexed by a signed modulo, whose possible bits also cover the other member,
  // is no combinational cycle, as it is written before reading the other member
  odd_t o;
  always_comb begin
    o.fold = '0;
    for (int i = 0; i < $bits(o.data); i++) o.fold[i%11] ^= o.data[i];
  end
  always_comb o.data = q[256:0];

  // Test: a member computed from more elements of an unpacked array, which other processes
  // write, than are checked one by one
  narrow_t m[100];
  always_comb begin
    m[0].x = '0;
    for (int i = 1; i < 100; i++) m[0].x = m[0].x ^ m[i].a ^ m[i].b;
  end
  for (genvar g = 1; g < 100; g++) begin : gen_m
    always_comb begin
      m[g].a = qa + 4'(g);
      m[g].b = qb;
    end
  end

  // Test: a write at positions all past its member, which writes nothing
  edge_t e;
  always_comb begin
    e.f = '0;
    e.f[3'd5+3'(k[0])] = 1'b1;
  end
  always_comb e.g = qb[2:0];

  // Test: members at constant positions
  narrow_t n;
  always_comb begin
    n.x = '0;
    n.x = n.a ^ n.b;
  end
  always_comb begin
    n.a = qa;
    n.b = qb;
  end

  // Test: members of an element of an unpacked array, also read at a variable index
  narrow_t u[16];
  always_comb begin
    u[2].x = '0;
    u[2].x = u[2].a ^ u[2].b;
  end
  always_comb begin
    u[2].a = qa;
    u[2].b = qb;
  end

  always @(posedge clk) begin
    if (cyc > 0) begin
      `checkh(w.par, parity(q));
      `checkh(s.par, parity(~q));
      `checkh(o.fold, fold(q[256:0]));
      `checkh(n.x, qa ^ qb);
      `checkh(u[k].x, qa ^ qb);
      `checkh(m[0].x, mfold(qa, qb));
      `checkh(e, {5'h0, qb[2:0]});
    end
    cyc <= cyc + 1;
    q <= {q[298:0], ~q[299]} ^ 300'(cyc * 32'h9e3779b9);
    qa <= qa + 4'd3;
    qb <= qb ^ 4'(cyc);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
