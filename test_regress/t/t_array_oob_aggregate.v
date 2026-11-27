// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An out-of-range element of an unpacked array reads the default value of its type
// (IEEE 1800-2023 7.4.5, Table 7-1): null for a class handle, empty for a queue or a
// dynamic or associative array, and, for a struct, the default of each member: X for a
// 4-state one (all ones with --x-assign 1), 0 for a 2-state one, or its initializer
class C;
  int x = 5;
endclass

interface ifc;
endinterface

module t;
  typedef struct {
    logic [7:0] tag;
    bit [7:0] data;
    int q[$];
    C h;
  } mixed_t;
  typedef struct {
    bit [7:0] x = 8'h39;
    bit [7:0] y;
    int q[$];
  } init_t;
  // A nonexistent element of a container read as a default reads its element default
  typedef struct {bit [7:0] v = 8'h5a;} elem_t;
  typedef struct {
    elem_t q[$];
    elem_t aa[int];
  } cont_t;
  // A virtual interface reads null
  typedef struct {
    virtual ifc vi;
    bit [7:0] x = 8'h3a;
  } vif_t;
  // An unpacked union has no default value built, but a member read beside it still reads its
  // default
  typedef union {
    int a;
    bit [7:0] b;
  } u_t;
  typedef struct {
    u_t u;
    bit [7:0] x = 8'h39;
    bit [7:0] y;
  } un_t;

  C ch[3];
  int qa[3][$];
  int da[3][];
  int aa[3][string];
  mixed_t ma[3];
  init_t ia[3];
  cont_t ca[3];
  ifc i0 ();
  vif_t va[3];
  vif_t vw;
  un_t ua[3];
  mixed_t mw;
  init_t iw;
  int idx;

  initial begin
    foreach (ch[i]) ch[i] = new;
    foreach (qa[i]) qa[i] = '{i + 1};
    foreach (da[i]) da[i] = '{i + 1, i + 2};
    foreach (aa[i]) aa[i]["k"] = i;
    foreach (ma[i]) begin
      ma[i].tag = 8'h44;
      ma[i].data = 8'h78;
      ma[i].q = '{42};
      ma[i].h = new;
    end
    foreach (ia[i]) begin
      ia[i].x = 8'h91 + 8'(i);
      ia[i].y = 8'h51;
      ia[i].q = '{7};
    end
    foreach (va[i]) begin
      va[i].vi = i0;
      va[i].x = 8'h11;
    end
    foreach (ua[i]) begin
      ua[i].u.a = 5;
      ua[i].x = 8'h11;
      ua[i].y = 8'h22;
    end
    foreach (ca[i]) begin
      ca[i].q = '{'{v: 8'h11}};
      ca[i].aa[7] = '{v: 8'h22};
    end
    for (idx = 2; idx <= 3; ++idx) begin
      `checkh(ch[idx] == null, idx == 3);
      `checkh(qa[idx].size(), idx == 3 ? 0 : 1);
      `checkh(da[idx].size(), idx == 3 ? 0 : 2);
      `checkh(aa[idx].num(), idx == 3 ? 0 : 1);
      // A member read directly, and the whole struct
      `checkh(ma[idx].tag, idx == 3 ? 8'hff : 8'h44);
      `checkh(ma[idx].data, idx == 3 ? 8'h00 : 8'h78);
      `checkh(ma[idx].q.size(), idx == 3 ? 0 : 1);
      `checkh(ma[idx].h == null, idx == 3);
      mw = ma[idx];
      `checkh(mw.tag, idx == 3 ? 8'hff : 8'h44);
      `checkh(mw.data, idx == 3 ? 8'h00 : 8'h78);
      `checkh(mw.q.size(), idx == 3 ? 0 : 1);
      `checkh(mw.h == null, idx == 3);
      `checkh(ia[idx].x, idx == 3 ? 8'h39 : 8'h93);
      `checkh(ia[idx].y, idx == 3 ? 8'h00 : 8'h51);
      iw = ia[idx];
      `checkh(iw.x, idx == 3 ? 8'h39 : 8'h93);
      `checkh(iw.y, idx == 3 ? 8'h00 : 8'h51);
      `checkh(iw.q.size(), idx == 3 ? 0 : 1);
      `checkh(ca[idx].q[0].v, idx == 3 ? 8'h5a : 8'h11);
      `checkh(ca[idx].aa[7].v, idx == 3 ? 8'h5a : 8'h22);
      `checkh(ca[idx].aa[8].v, 8'h5a);
      `checkh(va[idx].vi == null, idx == 3);
      vw = va[idx];
      `checkh(vw.vi == null, idx == 3);
      `checkh(vw.x, idx == 3 ? 8'h3a : 8'h11);
      `checkh(ua[idx].x, idx == 3 ? 8'h39 : 8'h11);
      `checkh(ua[idx].y, idx == 3 ? 8'h00 : 8'h22);
      `checkh(ua[idx].u.a, idx == 3 ? 0 : 5);
      `checkh(ua[idx].x[3:0], idx == 3 ? 4'h9 : 4'h1);
      `checkh(ua[idx].y[7:4], idx == 3 ? 4'h0 : 4'h2);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
