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

    // item.index is each element's index (IEEE 1800-2023 7.12.4)
    q = '{5, 4, 3, 2, 1};
    i = q.sum with (item.index);
    `checkh(i, 32'ha);
    i = q.product with (item.index + 1);
    `checkh(i, 32'd120);
    i = q.and with (item.index + 9);
    `checkh(i, 32'h8);
    i = q.or with (item.index);
    `checkh(i, 32'h7);
    i = q.xor with (item.index);
    `checkh(i, 32'h4);
    qv = q.min with (4 - item.index);
    `checkp(qv, "'{'h1}");
    qv = q.max with (item.index);
    `checkp(qv, "'{'h1}");
    qv = q.unique with (item.index / 2);
    `checkp(qv, "'{'h5, 'h3, 'h1}");
    begin
      byte bq[3];
      byte bqv[$];
      bq = '{1, 1, 1};
      bqv = bq.unique with (item.index * 256);
      `checkp(bqv, "'{'h1, 'h1, 'h1}");
      qi = bq.unique_index with (item.index * 256);
      `checkp(qi, "'{'h0, 'h1, 'h2}");
    end
    begin
      longint lq[3];
      longint lqv[$];
      lq = '{64'h1_0000_0000, 5, 2};
      lqv = lq.max with (item);
      `checkp(lqv, "'{'h100000000}");
      lqv = lq.min with (item);
      `checkp(lqv, "'{'h2}");
    end

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

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
