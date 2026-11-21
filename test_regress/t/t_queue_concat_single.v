// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

// Unpacked array concatenations of strings, and of a single item

package p;
  typedef string str_q[$];
  str_q causes = {"a", "b"};
  str_q status = {"c"};
endpackage

class Cls;
  int x;
endclass

module t;
  typedef string str_q[$];
  typedef struct {int a; int b;} s_t;
  typedef struct packed {logic [7:0] a; logic [7:0] b;} ps_t;
  typedef enum {A, B, C} e_t;
  s_t sq[$];
  s_t sd[];
  ps_t pq[$];
  e_t eq[$];
  logic [1:0][7:0] paq[$];
  shortint shq[$];
  byte by1;
  byte by2;
  string s[$];
  string r[$];
  string d[];
  string e[];
  string u[2];
  string u2[2];
  string b[$:3];
  string one;
  int iq[$];
  int ir[$];
  int iqq[$][$];
  int iu[2];
  int iu2[2];
  int id[];
  Cls cq[$];
  Cls cr[$];

  function automatic str_q get(int sel);
    str_q result;
    if (sel == 0) result = {p::causes, p::status, "d"};
    else result = {p::causes};
    return result;
  endfunction
  function automatic str_q ret(str_q q);
    return {q};
  endfunction
  function automatic int cnt(str_q q);
    return q.size();
  endfunction

  initial begin
    Cls c;
    `checkp(get(0), "'{\"a\", \"b\", \"c\", \"d\"}");
    `checkp(get(1), "'{\"a\", \"b\"}");
    one = "z";
    s = {"x", one, "y"};
    r = {s};
    `checkp(r, "'{\"x\", \"z\", \"y\"}");
    r = {"w"};
    `checkp(r, "'{\"w\"}");
    r = {one};
    `checkp(r, "'{\"z\"}");
    d = {s};
    `checkp(d, "'{\"x\", \"z\", \"y\"}");
    e = {d};
    `checkp(e, "'{\"x\", \"z\", \"y\"}");
    u = '{"m", "n"};
    r = {u};
    `checkp(r, "'{\"m\", \"n\"}");
    u2 = {u};
    `checkp(u2[0], "\"m\"");
    `checkp(u2[1], "\"n\"");
    b = {s};
    `checkp(b, "'{\"x\", \"z\", \"y\"}");
    r = {b};
    `checkp(r, "'{\"x\", \"z\", \"y\"}");
    `checkp(ret(s), "'{\"x\", \"z\", \"y\"}");
    `checkd(cnt({s}), 3);
    `checkd(cnt({p::status}), 1);
    r = {p::causes, s, "q"};
    `checkp(r, "'{\"a\", \"b\", \"x\", \"z\", \"y\", \"q\"}");

    iq = {1, 2};
    ir = {iq};
    `checkp(ir, "'{'h1, 'h2}");
    iqq = {iq};
    `checkp(iqq, "'{'{'h1, 'h2}}");
    iu = '{3, 4};
    iu2 = {iu};
    `checkp(iu2, "'{'h3, 'h4}");
    id = {iu};
    `checkp(id, "'{'h3, 'h4}");

    // Nested concatenations are elements (IEEE 1800-2023 10.10.3)
    r = {{"a", one}};
    `checkp(r, "'{\"az\"}");
    r = {"x", {"a", one}, {2{one}}};
    `checkp(r, "'{\"x\", \"az\", \"zz\"}");
    by1 = 1;
    by2 = 2;
    shq = {{by1, by2}};
    `checkp(shq, "'{'h102}");
    shq = {3, {by1, by2}};
    `checkp(shq, "'{'h3, 'h102}");
    shq = {4, {2{by1}}};
    `checkp(shq, "'{'h4, 'h101}");
    iqq = {{4, 5, 6}, {7}};
    `checkp(iqq, "'{'{'h4, 'h5, 'h6}, '{'h7}}");

    // Assignment pattern items
    sq = {'{1, 2}};
    `checkp(sq, "'{'{a:'h1, b:'h2}}");
    sq = {'{3, 4}, '{5, 6}, sq};
    `checkp(sq, "'{'{a:'h3, b:'h4}, '{a:'h5, b:'h6}, '{a:'h1, b:'h2}}");
    sd = {'{7, 8}};
    `checkp(sd, "'{'{a:'h7, b:'h8}}");
    pq = {'{8'h1, 8'h2}};
    `checkp(pq, "'{'h102}");
    pq = {'{8'h3, 8'h4}, '{8'h5, 8'h6}};
    `checkp(pq, "'{'h304, 'h506}");
    ir = {'{1, 2}, 3};
    `checkp(ir, "'{'h1, 'h2, 'h3}");
    ir = {'{4, 5}};
    `checkp(ir, "'{'h4, 'h5}");
    iqq = {'{6, 7}};
    `checkp(iqq, "'{'{'h6, 'h7}}");
    eq = {'{A, C}};
    `checkp(eq, "'{'h0, 'h2}");
    paq = {'{8'h1, 8'h2}};
    `checkp(paq, "'{'h102}");

    c = new;
    c.x = 5;
    cq.push_back(c);
    cr = {cq};
    `checkd(cr.size(), 1);
    `checkd(cr[0].x, 5);
    cr = {'{c, null}, c};
    `checkd(cr.size(), 3);
    if (cr[1] != null || cr[2] != c) `stop;
    cr = {null};
    `checkd(cr.size(), 1);
    if (cr[0] != null) `stop;

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
