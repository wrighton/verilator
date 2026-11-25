// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A part-select partly above a packed array element, at an element index mostly out of range,
// reads the bits of the element in range
module t;
  localparam realtime STEP = 1;
  logic [8:0] s;
  logic [62:0] a;
  logic [0:-2][22:2] v;
  logic [16:0] r;
  assign v = a;
  assign r = v[s][8+:17];
  logic [0:-2][44:2] w;
  logic [16:0] q;
  assign w = {a, a, 3'(s)};
  assign q = w[s][30+:17];

  // A bit of an element of a packed array at a position given by a part-select at a variable
  // position
  bit [3:0][7:0] e;
  bit [3:0] pick;
  bit [1:0] ei;
  bit [1:0] ej;
  bit eb;
  assign eb = e[ei][pick[ej+:3]];

  // A bit of a member of an element of a wide row of a packed array of structures
  typedef struct packed {
    bit [2:0] x;
    bit [23:0] y;
  } s1_t;
  s1_t [33:0][2:0] m;
  bit [5:0] m5;
  bit [7:0] m4;
  bit [7:0] m2;
  bit mb;
  // verilator lint_off WIDTHTRUNC
  assign mb = m[m5][m4].x[m2];
  // verilator lint_on WIDTHTRUNC

  // Reads of members of the same element of a wide row
  typedef struct packed {
    logic [2:0] x;
    logic [23:0] y;
  } l1_t;
  l1_t [33:0][2:0] lm;
  logic [2:0] l5;
  logic [7:0] l4;
  logic [23:0] ly;
  logic [2:0] lyp;
  logic [2753:0] lv;
  // verilator lint_off WIDTHTRUNC
  assign ly = lm[l5][l4].y;
  assign lyp = lm[l5][l4].y[l4+:3];
  // verilator lint_on WIDTHTRUNC

  initial begin
    for (int i = 0; i < 512; ++i) begin
      lm = 2754'({43{64'h0f0f_5aa5_9876_1234 * 64'(i + 1)}});
      l5 = 3'(i * 5);
      l4 = 8'(i * 7 >> 1);
      lv = lm;
      #STEP;
      if (l4 < 3) begin
        `checkh(ly, 24'(lv >> (l5 * 81 + l4 * 27)));
        `checkh(lyp, 3'(lv >> (l5 * 81 + l4 * 28)));
      end
    end
  end

  // Reads of two members of the same element of a wide row
  l1_t [33:0][2:0] km;
  logic [2:0] k5;
  logic [7:0] k4;
  logic [23:0] ky;
  logic [2:0] kx;
  logic [2753:0] kv;
  // verilator lint_off WIDTHTRUNC
  assign ky = km[k5][k4].y;
  assign kx = km[k5][k4].x;
  // verilator lint_on WIDTHTRUNC

  initial begin
    for (int i = 0; i < 512; ++i) begin
      km = 2754'({43{64'h5a0f_a5f0_1234_9876 * 64'(i + 3)}});
      kv = km;
      k5 = 3'(i * 3);
      k4 = 8'(i * 5 >> 1);
      #STEP;
      if (k4 < 3) begin
        `checkh(ky, 24'(kv >> (k5 * 81 + k4 * 27)));
        `checkh(kx, 3'(kv >> (k5 * 81 + k4 * 27 + 24)));
      end
    end
  end

  initial begin
    for (int i = 0; i < 512; ++i) begin
      m = 2754'({43{64'h5aa5_0f0f_1234_9876 * 64'(i + 1)}});
      m5 = 6'(i * 7);
      m4 = 8'(i * 3 >> 2);
      m2 = 8'(i >> 5);
      #STEP;
      `checkh(mb, m5 < 34 && m4 < 3 && m2 < 3 ? 1'(m >> (m5 * 81 + m4 * 27 + 24 + m2)) : 1'b0);
    end
  end

  initial begin
    for (int i = 0; i < 512; ++i) begin
      s = 9'(i);
      a = 63'h1234_5678_9abc_def1 * 63'(i + 1);
      #STEP;
      if (s == 0) `checkh(r[14:0], a[62:48]);
      if (s == 0) `checkh(q[14:0], a[62:48]);
      e = 32'(a);
      pick = 4'(i >> 3);
      ei = 2'(i >> 7);
      ej = 2'(i >> 1);
      #STEP;
      `checkh(eb, e[ei][3'(pick >> ej)]);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
