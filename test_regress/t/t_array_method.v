// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

module t;
  initial begin
    int q[5];
    int qv[$];  // Value returns
    int qi[$];  // Index returns
    int i;
    string v;

    q = '{1, 2, 2, 4, 3};
    `checkp(q, "'{'h1, 'h2, 'h2, 'h4, 'h3}");

    // NOT tested: with ... selectors

    q.sort;
    `checkp(q, "'{'h1, 'h2, 'h2, 'h3, 'h4}");
    q.sort with (item == 2);
    `checkp(q, "'{'h1, 'h3, 'h4, 'h2, 'h2}");
    q.sort(x) with (x == 3);
    `checkp(q, "'{'h1, 'h4, 'h2, 'h2, 'h3}");

    q.rsort;
    `checkp(q, "'{'h4, 'h3, 'h2, 'h2, 'h1}");
    q.rsort with (item == 2);
    `checkp(q, "'{'h2, 'h2, 'h4, 'h3, 'h1}");

    qv = q.unique;
    `checkp(qv, "'{'h2, 'h4, 'h3, 'h1}");
    qi = q.unique_index;
    qi.sort;
    `checkp(qi, "'{'h0, 'h2, 'h3, 'h4}");
    q.reverse;
    `checkp(q, "'{'h1, 'h3, 'h4, 'h2, 'h2}");
    q.shuffle();
    q.sort;
    `checkp(q, "'{'h1, 'h2, 'h2, 'h3, 'h4}");

    // These require an with clause or are illegal
    // TODO add a lint check that with clause is provided
    qv = q.find with (item == 2);
    `checkp(qv, "'{'h2, 'h2}");
    qv = q.find_first with (item == 2);
    `checkp(qv, "'{'h2}");
    qv = q.find_last with (item == 2);
    `checkp(qv, "'{'h2}");

    qv = q.find with (item == 20);
    `checkp(qv, "'{}");
    qv = q.find_first with (item == 20);
    `checkp(qv, "'{}");
    qv = q.find_last with (item == 20);
    `checkp(qv, "'{}");

    qi = q.find_index with (item == 2);
    qi.sort;
    `checkp(qi, "'{'h1, 'h2}");
    qi = q.find_first_index with (item == 2);
    `checkp(qi, "'{'h1}");
    qi = q.find_last_index with (item == 2);
    `checkp(qi, "'{'h2}");

    qi = q.find_index with (item == 20);
    qi.sort;
    `checkp(qi, "'{}");
    qi = q.find_first_index with (item == 20);
    `checkp(qi, "'{}");
    qi = q.find_last_index with (item == 20);
    `checkp(qi, "'{}");

    qv = q.min;
    `checkp(qv, "'{'h1}");
    qv = q.max;
    `checkp(qv, "'{'h4}");

    // Reduction methods

    i = q.sum;
    `checkh(i, 32'hc);
    i = q.product;
    `checkh(i, 32'h30);

    q = '{32'b1100, 32'b1010, 32'b1100, 32'b1010, 32'b1010};
    i = q.and;
    `checkh(i, 32'b1000);
    i = q.or;
    `checkh(i, 32'b1110);
    i = q.xor;
    `checkh(i, 32'ha);

    q = '{1, 2, 2, 4, 3};
    // `checkp(q, "'{1, 2, 2, 4, 3}");

    i = q.sum with (item + 1);
    `checkh(i, 32'h11);
    i = q.product with (item + 1);
    `checkh(i, 32'h168);

    q = '{32'b1100, 32'b1010, 32'b1100, 32'b1010, 32'b1010};
    i = q.and with (item + 1);
    `checkh(i, 32'b1001);
    i = q.or with (item + 1);
    `checkh(i, 32'b1111);
    i = q.xor with (item + 1);
    `checkh(i, 32'hb);

    // map method
    q = '{1, 2, 3, 4, 5};
    qv = q.map() with (item * 2);
    `checkp(qv, "'{'h2, 'h4, 'h6, 'h8, 'ha}");
    qv = q.map(x) with (x + x.index);
    `checkp(qv, "'{'h1, 'h3, 'h5, 'h7, 'h9}");

    // Original reproducer for #8827.
    begin
      bit [3:0] q[$];
      bit [3:0] v;
      bit [3:0] p;
      q = '{4'hF, 4'hF, 4'h1};
      v = q.sum();
      p = q.product();
      `checkh(q.sum(), 4'd15);
      `checkh(v, 4'd15);
      `checkh(q.sum() == 4'd15, 1'b1);
      `checkh($bits(q.sum()), 32'd4);
      `checkh(q.product(), 4'd1);
      `checkh(p, 4'd1);
    end

    // Reductions without 'with' return the element type (IEEE 1800-2023 7.12.3)
    begin
      typedef bit [6:0] elem_t;
      localparam bit [6:0] P[3] = '{100, 100, 1};
      localparam int PSUM = int'(P.sum());
      elem_t f[3:1];
      elem_t d[];
      elem_t q[$];
      elem_t a[int];
      f = '{100, 100, 1};
      d = '{100, 100, 1};
      q = '{100, 100, 1};
      a = '{1: 100, 2: 100, 3: 1};
      `checkh(int'(f.sum()), 73);
      `checkh($bits(f.sum()), 7);
      `checkh(int'(f.product()), 16);
      `checkh(PSUM, 73);
      `checkh(int'(f.sum()), int'(d.sum()));
      `checkh(int'(f.sum()), int'(q.sum()));
      `checkh(int'(f.sum()), int'(a.sum()));
      `checkh(int'(f.product()), int'(d.product()));
      `checkh(int'(f.product()), int'(q.product()));
      `checkh(f.sum() with (int'(item)), 201);
    end
    begin
      byte s[3];
      byte b[2];
      s = '{-100, -100, -100};
      `checkh(int'(s.sum()), -44);
      b = '{-2, 1};
      `checkh(int'(b.or()), -1);
      `checkh(int'(b.and()), 0);
      `checkh(int'(b.xor()), -1);
    end
    begin
      bit [64:0] w[2];
      w = '{'1, 2};
      `checkh(96'(w.sum()), 96'h1);
      `checkh(96'(w.product()), 96'h1_ffff_ffff_ffff_fffe);
    end
    begin
      typedef enum bit [1:0] {E0, E1, E2, E3} enum_t;
      enum_t e[3];
      enum_t ev;
      e = '{E3, E2, E1};
      ev = e.sum();
      `checkh(ev, E2);
      `checkh(int'(e.sum()), 2);
    end
    begin
      typedef struct packed {
        bit [2:0] hi;
        bit [3:0] lo;
      } struct_t;
      struct_t ps[3];
      ps = '{'{7, 15}, '{7, 15}, '{0, 2}};
      `checkh(int'(ps.sum()), 0);
    end
    begin
      bit [6:0] m[2][1:3];
      m = '{'{1, 1, 1}, '{100, 100, 1}};
      `checkh(int'(m[1].sum()), 73);
    end
    // A reduction as a self-determined operand of a logical operator, ?: and if
    begin
      bit b[3];
      bit [6:0] m[2];
      bit r;
      b = '{1'b0, 1'b1, 1'b0};
      m = '{7'd100, 7'd28};
      r = b.or() && b.xor();
      `checkh(r, 1'b1);
      r = b.and() || !b.or();
      `checkh(r, 1'b0);
      r = !b.and();
      `checkh(r, 1'b1);
      r = b.sum() -> b.product();
      `checkh(r, 1'b0);
      `checkh(b.or() ? 7'd5 : 7'd6, 7'd5);
      // A multi-bit value as a logical operand
      // verilator lint_off WIDTHTRUNC
      if (m.sum() || m.and()) r = 1;
      else r = 0;
      `checkh(r, 1'b1);
      if (m.sum() && m.and()) r = 1;
      else r = 0;
      `checkh(r, 1'b0);
      r = m.or() && m.xor() && !m.sum();
      `checkh(r, 1'b1);
      `checkh(m.product() ? 7'd3 : 7'd4, 7'd3);
      // verilator lint_on WIDTHTRUNC
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
