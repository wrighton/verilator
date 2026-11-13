// DESCRIPTION: Verilator: Verilog Test module
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

typedef struct {
  int x;
  int y;
} pair_t;

class Cls;
  int q[$];
  int d[];
  int m[int];
  pair_t s;
  int aq[int][$];
  function void filter(int v);
    foreach (aq[k]) aq[k] = aq[k].find with (item != v);
  endfunction
endclass

typedef struct {
  int q[$];
} qs_t;

module t (
    input clk
);

  integer i;
  reg [94:0] w95;
  reg [399:0] w400;

  integer cyc = 0;

  // Test loop
  always @(posedge clk) begin
`ifdef TEST_VERBOSE
    $write("[%0t] cyc==%0d\n", $time, cyc);
`endif
    cyc <= cyc + 1;
    if (cyc == 0) begin
      // Setup
      w95 = {95{1'b1}};
      w400 = '1;
    end
    else if (cyc == 1) begin
      if (w95++ != {95{1'b1}}) $stop;
      if (w95 != {95{1'b0}}) $stop;
      if (w95-- != {95{1'b0}}) $stop;
      if (w95 != {95{1'b1}}) $stop;
      if (++w95 != {95{1'b0}}) $stop;
      if (w95 != {95{1'b0}}) $stop;
      if (--w95 != {95{1'b1}}) $stop;
      if (w95 != {95{1'b1}}) $stop;

      if (w400++ != {400{1'b1}}) $stop;
      if (w400 != {400{1'b0}}) $stop;
      if (w400-- != {400{1'b0}}) $stop;
      if (w400 != {400{1'b1}}) $stop;
      if (++w400 != {400{1'b0}}) $stop;
      if (w400 != {400{1'b0}}) $stop;
      if (--w400 != {400{1'b1}}) $stop;
      if (w400 != {400{1'b1}}) $stop;
    end
    else if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Patterns assigned to a non-variable lvalue they also read
  initial begin
    Cls c1;
    Cls c2;
    int aq[2][$];
    c1 = new;
    c2 = new;

    c1.q = {1, 2};
    c2.q = {3};
    c1.q = {c1.q, c2.q};
    if ($sformatf("%p", c1.q) != "'{'h1, 'h2, 'h3}") $stop;

    c1.d = {4, 5};
    c1.d = {c1.d, c1.d};
    if ($sformatf("%p", c1.d) != "'{'h4, 'h5, 'h4, 'h5}") $stop;

    c1.m[2] = 6;
    c1.m[3] = 7;
    c1.m = '{1: c1.m[2], 2: c1.m[3]};
    if ($sformatf("%p", c1.m) != "'{'h1:'h6, 'h2:'h7}") $stop;

    c1.s = '{8, 9};
    c1.s = '{c1.s.y, c1.s.x};
    if ($sformatf("%p", c1.s) != "'{x:'h9, y:'h8}") $stop;

    aq[0] = {10};
    aq[1] = {11};
    aq[1] = {aq[1], aq[0]};
    if ($sformatf("%p", aq) != "'{'{'ha}, '{'hb, 'ha}}") $stop;
  end

  // Array method 'with' results assigned to a non-variable lvalue they also read
  initial begin
    Cls c;
    int dq[][$];
    int qq[$][$];
    qs_t sa[2];
    c = new;

    c.aq[1] = {2, 3, 4};
    c.aq[5] = {3, 1};
    c.filter(3);
    if ($sformatf("%p", c.aq) != "'{'h1:'{'h2, 'h4}, 'h5:'{'h1}}") $stop;

    dq = new[3];
    dq[0] = {1, 2, 3, 2};
    dq[1] = {2, 5};
    foreach (dq[i]) dq[i] = dq[i].find_index with (item == 2);
    dq[2] = dq[0].find_last with (item > 1);
    if ($sformatf("%p", dq) != "'{'{'h1, 'h3}, '{'h0}, '{'h3}}") $stop;

    qq = '{'{4, 5, 6}, '{6, 6, 7}};
    qq[0] = qq[0].find_first with (item > 4);
    qq[1] = qq[1].unique with (item);
    qq.push_back(qq[1].max with (item));
    qq[2][0] = qq[1].sum with (item * 2);
    if ($sformatf("%p", qq) != "'{'{'h5}, '{'h6, 'h7}, '{'h1a}}") $stop;

    sa[0].q = {7, 3, 9};
    sa[1].q = {2};
    foreach (sa[i]) sa[i].q = sa[i].q.min with (item);
    sa[1].q[0] = sa[0].q.product with (item + 1);
    if ($sformatf("%p", sa) != "'{'{q:'{'h3}}, '{q:'{'h4}}}") $stop;
  end
endmodule
