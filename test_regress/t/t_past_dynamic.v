// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Sampled value functions of strings, class handles and dynamic variables, also of their
// methods, elements and members, whose default sampled values before the first tick are those of
// the empty variables (IEEE 1800-2023 16.9.3, 16.5.1)
module t;
  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;

  typedef struct {
    int a;
    bit [5:0] b;
  } us_t;
  typedef int iq_t[$];
  iq_t q;
  int d[];
  int aa[int];
  string s;
  us_t us;
  us_t sa[3];
  int aq[3][$];
  string qs[$];
  // Changed between the clock edges
  always @(negedge clk) begin
    cyc <= cyc + 1;
    q.push_back(cyc + 3);
    d = new[cyc % 4];
    if (d.size() > 0) d[0] = cyc + 9;
    aa[cyc] = cyc;
    s = {s, "x"};
    us.a = cyc * 5;
    sa[2].a = cyc * 3;
    aq[1].push_back(cyc);
    qs.push_back(cyc % 2 == 1 ? "ab" : "abc");
  end

  // Models of the sampled values at the previous tick
  int hqsize = 0, hdsize = 0, haanum = 0, hslen = 0, hq0 = 0, hqcyc = 0, hqlast = 0, hd0 = 0;
  int husa = 0, hsaa = 0, haqsize = 0, hqslen = 0;
  always @(posedge clk) begin
    `checkh($past(q.size()), hqsize);
    `checkh($past(d.size()), hdsize);
    `checkh($past(aa.num()), haanum);
    `checkh($past(s.len()), hslen);
    `checkh($past(q[0]), hq0);
    `checkh($past(q[cyc]), hqcyc);
    `checkh($past(q[$]), hqlast);
    `checkh($past(d[0]), hd0);
    `checkh($past(us.a), husa);
    `checkh($stable(us.a), us.a == husa);
    `checkh($past(sa[2].a), hsaa);
    `checkh($past(aq[1].size()), haqsize);
    `checkh($past(qs[0].len()), hqslen);
    `checkh($changed(q[0]), (q.size() > 0 ? q[0] : 0) != hq0);
    `checkh($rose(q[$]), (q.size() > 0 ? q[$][0] : 1'b0) && !hqlast[0]);
    hqsize <= q.size();
    hdsize <= d.size();
    haanum <= aa.num();
    hslen <= s.len();
    hq0 <= q.size() > 0 ? q[0] : 0;
    hqcyc <= q.size() > cyc ? q[cyc] : 0;
    hqlast <= q.size() > 0 ? q[$] : 0;
    hd0 <= d.size() > 0 ? d[0] : 0;
    husa <= us.a;
    hsaa <= sa[2].a;
    haqsize <= aq[1].size();
    hqslen <= qs.size() > 0 ? qs[0].len() : 0;
  end
  assert property (@(posedge clk) $past(q.size()) == hqsize);
  assert property (@(posedge clk) $past(aq[1].size()) == haqsize);

  // Whole strings, class handles and dynamic variables, also as elements or members
  class C;
    int v;
  endclass
  typedef struct {
    int a;
    int q[$];
  } sq_t;
  C h;
  C ha[2];
  C hnew = new;
  string sarr[2];
  sq_t sq;
  real rq[$];
  real ra[2];
  always @(negedge clk) begin
    if (cyc == 3) h = hnew;
    if (cyc == 5) ha[1] = hnew;
    if (cyc % 3 == 0) sarr[cyc%2] = {sarr[cyc%2], "y"};
    sq.a = cyc;
    if (cyc % 2 == 0) sq.q.push_back(cyc);
    if (cyc % 3 == 1) rq.push_back(cyc * 0.5);
    ra[cyc%2] = cyc * 1.5;
  end
  iq_t hq;
  int hd[];
  string hs;
  C hh;
  C hha[2];
  string hsarr[2];
  int haq[3][$];
  sq_t hsq;
  sq_t tsq;
  real hrq[$];
  real hra[2];
  always @(posedge clk) begin
    `checkh($past(q) == hq, 1'b1);
    `checkh($sampled(q) == q, 1'b1);
    `checkh($stable(d), d == hd);
    `checkh($past(s) == hs, 1'b1);
    `checkh($changed(s), s != hs);
    `checkh($past(h) == hh, 1'b1);
    `checkh($changed(h), h != hh);
    `checkh($past(ha) == hha, 1'b1);
    `checkh($stable(sarr), sarr == hsarr);
    `checkh($past(aq) == haq, 1'b1);
    tsq = $past(sq);
    `checkh(tsq.a, hsq.a);
    `checkh(tsq.q == hsq.q, 1'b1);
    `checkh($past(rq) == hrq, 1'b1);
    `checkh($stable(rq), rq == hrq);
    `checkh($past(ra) == hra, 1'b1);
    `checkh($changed(ra), ra != hra);
    hq <= q;
    hd <= d;
    hs <= s;
    hh <= h;
    hha <= ha;
    hsarr <= sarr;
    haq <= aq;
    hsq <= sq;
    hrq <= rq;
    hra <= ra;
  end
  assert property (@(posedge clk) $past(s) == hs && $stable(h) == (h == hh));
  property p_stable(x, y);
    @(posedge clk) $stable(x) == y;
  endproperty
  assert property (p_stable(q, q == hq));
  assert property (p_stable(sarr, sarr == hsarr));

  initial begin
    #100;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
