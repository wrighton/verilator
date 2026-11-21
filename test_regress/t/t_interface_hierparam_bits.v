// DESCRIPTION: Verilator: Verilog Test module
//
// $bits() of interface member signals used as a child module parameter value.
// $bits reads the type, not the hierarchical value, so it is legal in a
// parameter (IEEE 1800-2023 6.20.2 forbids hierarchical values only).
// Also when the interface port is connected to a hierarchical reference.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface axi_if #(
    parameter int ID_W = 8,
    parameter int ADDR_W = 32
);
  logic [ID_W-1:0] AWID;
  logic [ADDR_W-1:0] AWADDR;
  logic [7:0] AWLEN;
endinterface

module chkmod #(
    parameter int PAYLOAD_WIDTH = 1,
    parameter int EXPECT = 1
);
  initial `checkh(PAYLOAD_WIDTH, EXPECT);
endmodule

module bridge #(
    parameter int EXPECT = 1
) (
    axi_if axi
);
  // $bits of a concat of interface members
  chkmod #(
      .PAYLOAD_WIDTH($bits({axi.AWID, axi.AWADDR, axi.AWLEN})),
      .EXPECT(EXPECT)
  ) u_concat ();
  // $bits of a single interface member
  chkmod #(
      .PAYLOAD_WIDTH($bits(axi.AWADDR)),
      .EXPECT(EXPECT - 12 - 8)
  ) u_single ();
  // $bits of an interface member in a generate condition
  if ($bits(axi.AWID) != 12) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endmodule

// Interface instances reached by hierarchical references as interface port actuals
interface harness #(
    parameter int ADDR_W = 32
);
  axi_if #(
      .ID_W(12),
      .ADDR_W(ADDR_W)
  ) axi ();
endinterface

interface outer;
  harness #(.ADDR_W(24)) h ();
endinterface

module holder #(
    parameter int ADDR_W = 40
);
  axi_if #(
      .ID_W(12),
      .ADDR_W(ADDR_W)
  ) axi ();
endmodule

module bind_target;
endmodule

module port_holder (
    axi_if src
);
  axi_if #(
      .ID_W(12),
      .ADDR_W($bits(src.AWADDR))
  ) axi ();
endmodule

module chain_holder;
  harness h ();
  port_holder p (.src(h.axi));
endmodule

module local_holder #(
    parameter int ADDR_W = 32
);
  axi_if #(
      .ID_W(12),
      .ADDR_W(ADDR_W)
  ) axi ();
  port_holder p (.src(axi));
endmodule

module cycle_holder (
    axi_if src
);
  axi_if axi ();
endmodule

module fan_holder (
    axi_if s0,
    axi_if s1
);
  axi_if #(
      .ID_W(12),
      .ADDR_W($bits(s0.AWADDR) + $bits(s1.AWADDR) - 16)
  ) axi ();
endmodule

interface outer_p #(
    parameter int ADDR_W = 32
);
  harness #(.ADDR_W(ADDR_W)) h ();
endinterface

module mid_outer (
    outer_p o
);
  bridge #(.EXPECT(34)) dut (.axi(o.h.axi));
endmodule

interface wrap_if #(
    parameter int EXPECT = 1
) (
    axi_if axi
);
  if ($bits({axi.AWID, axi.AWADDR, axi.AWLEN}) != EXPECT) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endinterface

module dp_leaf #(
    parameter int P = 1
);
endmodule

module dp_holder (
    axi_if s
);
  axi_if axi ();
  dp_leaf l ();
endmodule

module bm_relay (
    axi_if src
);
  axi_if #(
      .ID_W(12),
      .ADDR_W($bits(src.AWADDR))
  ) axi ();
endmodule

interface bm_outer;
  axi_if #(
      .ID_W(12),
      .ADDR_W(15)
  ) b ();
endinterface

interface bm_width #(
    parameter int DUMMY = 1
) (
    axi_if axi
);
  localparam int W = $bits(axi.AWADDR);
endinterface

module plain_sink (
    axi_if axi
);
endmodule

interface tp_if #(
    parameter int W = 32
);
  logic [W-1:0] a;
endinterface

module tp_ph #(
    parameter int K = 1
) (
    tp_if src
);
  tp_if #(.W(K)) out ();
endmodule

module tp_holder;
  tp_if #(.W(40)) loc ();
  tp_ph #(.K($bits(loc.a))) p (.src(loc));
endmodule

module tp_sink (
    tp_if bus
);
endmodule

// A parameter value of an instance on a path referring to another instance through a variable,
// type or function
interface tq_if #(
    parameter int W = 7
);
  logic [W-1:0] a;
endinterface

module tq_ph #(
    parameter int K = 1
) (
    tq_if src
);
  tq_if #(.W(K)) out ();
endmodule

module tq_sink (
    tq_if bus
);
endmodule

module tq_chk #(
    parameter int EXPECT = 7
) (
    tq_if bus
);
  localparam int W = $bits(bus.a);
  if (W != EXPECT) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endmodule

module tq_localparam;
  tq_if #(.W(31)) loc ();
  localparam int K = $bits(loc.a);
  tq_ph #(.K(K)) p (.src(loc));
endmodule

module tq_dtype;
  tq_if #(.W(31)) loc ();
  logic [$bits(loc.a)-1:0] tmp;
  tq_ph #(.K($bits(tmp))) p (.src(loc));
endmodule

module tq_typedef;
  tq_if #(.W(31)) loc ();
  typedef logic [$bits(loc.a)-1:0] tmp_t;
  tq_ph #(.K($bits(tmp_t))) p (.src(loc));
endmodule

module tq_function;
  tq_if #(.W(31)) loc ();
  function automatic int k();
    return $bits(loc.a);
  endfunction
  tq_ph #(.K(k())) p (.src(loc));
endmodule

module tq_twice;
  tq_if #(.W(31)) loc ();
  localparam int L = 3;
  tq_ph #(.K(L + L)) p (.src(loc));
endmodule

// A defparam of an instance on a path, in a module specialized after the reference
interface dq_if #(
    parameter int W = 1,
    parameter int V = 1
);
  axi_if #(.ADDR_W(W + V)) axi ();
endinterface

module dq_chk #(
    parameter int EXPECT = 33
) (
    axi_if axi
);
  if ($bits(axi.AWADDR) != EXPECT) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endmodule

module dq_holder;
  dq_if #(.W(4)) x ();
  defparam x.V = 29;
  dq_if #(.W(5)) y ();
  generate
    begin
      defparam y.V = 28;
    end
    begin : g_z
      dq_if z ();
      defparam z.V = 31;
    end
  endgenerate
endmodule

// The same with defparam values not constant
module dn_holder;
  localparam int L = 29;
  dq_if #(.W(4)) x ();
  defparam x.V = L;
endmodule

module dm_holder #(
    parameter bit EN = 1
);
  dq_if #(.W(4)) x ();
  defparam x.V = EN ? 29 : 1;
endmodule

// With values from functions and type parameters, also replacing the value of an enclosing one
module du_holder;
  function automatic int f();
    return 29;
  endfunction
  dq_if #(.W(4)) x ();
  defparam x.V = f();
endmodule

module dt_holder #(
    parameter type T = logic [28:0]
);
  dq_if #(.W(4)) x ();
  defparam x.V = $bits(T);
endmodule

// A defparam of an unrelated parameter of an instance on a path, from a function
module df_holder;
  function automatic int f();
    return 11;
  endfunction
  dq_if #(
      .W(4),
      .V(29)
  ) x ();
  tx_if y ();
  defparam y.W = f();
endmodule

// A value the copy does not resolve, so left to its turn
module dl_sink (
    axi_if axi
);
endmodule

class dl_cls #(
    int N = 1
);
  localparam int W = N + 4;
endclass

module dl_holder;
  typedef dl_cls#(24) ct;
  localparam int L = ct::W;
  dq_if #(.W(4)) x ();
  defparam x.V = L;
endmodule

module tq_type #(
    parameter type T = logic [6:0]
);
  tq_if #(.W(31)) loc ();
  tq_ph #(.K($bits(T))) p (.src(loc));
endmodule

// A container of an instance on a path, specialized with its defaults later, evaluated only then,
// so the reference is left to its turn, and other specializations are not changed
module tm_localparam #(
    parameter int P = 3
);
  localparam int L = P * 2 + 2;
  tq_if #(.W(L)) b ();
endmodule

module tm_derived #(
    parameter int P = 3,
    parameter int Q = P + 5
);
  tq_if #(.W(Q)) b ();
endmodule

package tm_pkg2;
  localparam int K = 4;
endpackage

module tm_pkgref #(
    parameter int P = 3
);
  tq_if #(.W(tm_pkg2::K + P)) b ();
endmodule

// The same with a hierarchical interface port actual inside
module tm_relay (
    tq_if src
);
  tq_if #(.W($bits(src.a) + 1)) out ();
endmodule

module tm_nest #(
    parameter int P = 3
);
  tm_derived #(.P(P)) d ();
  tm_relay r (.src(d.b));
endmodule

module tm_tsize #(
    parameter type T = logic [4:0],
    parameter int P = $bits(T)
);
  tq_if #(.W(P)) b ();
endmodule

module tm_port #(
    parameter int P = 3
) (
    tq_if src
);
  tq_if #(.W(P + 2)) b ();
endmodule

// A parameter referring to a variable
module tm_varsize #(
    parameter int P = 3
);
  logic [P-1:0] v;
  localparam int L = $bits(v) + 2;
  tq_if #(.W(L)) b ();
endmodule

// Two-state values each used only after cleaned
module tm_order #(
    parameter int P = 3
);
  localparam bit [3:0] B = 4'bx101;
  localparam int C = int'(B) + P;
  localparam int A = int'(B) + C;
  tq_if #(.W(A)) b ();
endmodule

// The same, reached through the type of a variable
module tm_order_var #(
    parameter int P = 3
);
  localparam bit [3:0] B = 4'bx101;
  logic [B-1:0] v;
  localparam int A = $bits(v) + P;
  tq_if #(.W(int'(B) - 5 + A)) b ();
endmodule

// The same, reached through the base type of an enum
module tm_order_enum #(
    parameter int P = 3
);
  localparam bit [3:0] B = 4'bx101;
  typedef enum logic [B-1:0] {
    E0 = 2,
    E = 3
  } e_t;
  localparam int A = $bits(E) + P + int'(E) - int'(E0) - 1;
  tq_if #(.W(A)) b ();
endmodule

// A defparam in a module specialized already when copied for a second consumer
module tm_dpspec #(
    parameter int P = 5
);
  typedef logic [P:0] d_t;
  d_t v;
  tq_if b ();
  defparam b.W = $bits(v);
endmodule

// A parameter value from an enum of a type parameter, sized already
module tm_pval #(
    parameter int P = 1
);
  tq_if #(.W(P)) b ();
endmodule

// A recursive module whose consumer precedes the next level
module tm_rec #(
    parameter int N = 3
);
  tq_if #(.W(N + 2)) b ();
  if (N > 0) begin : g
    tq_chk #(.EXPECT(N + 1)) c (.bus(r.b));
    tm_rec #(.N(N - 1)) r ();
  end
endmodule

// An interface port connected to an interface visited already with its defaults
interface tm_vif #(
    parameter int K = 9
);
  logic [K-1:0] x;
endinterface

module tm_vsink (
    tq_if bus
);
endmodule

module tm_vholder (
    tm_vif s
);
  tq_if #(.W($bits(s.x) * 2 - $bits(s.x))) b ();
endmodule

// The same through instances of it, with its defaults or not
module tm_vcholder;
  tm_vif g ();
  tm_vif #(.K(4)) g4 ();
  tq_if #(.W($bits(g.x))) b ();
  tq_if #(.W($bits(g4.x) + 1)) b4 ();
endmodule

module tm_vcsink (
    tq_if bus
);
endmodule

module tm_vcsink4 (
    tq_if bus
);
endmodule

module tm_vcmiddle;
  tm_vcsink c (.bus(h.b));
  tm_vcsink4 c4 (.bus(h.b4));
  tm_vcholder h ();
endmodule

module tm_vmiddle (
    tm_vif s
);
  tq_chk #(.EXPECT(9)) c (.bus(h.b));
  tm_vholder h (.s(s));
endmodule

// A container with a parameterized class of its own, specialized after its original is kept
module tm_nholder #(
    parameter int Q = 1
);
  tq_if #(.W(Q)) b ();
endmodule

module tm_ncls #(
    parameter int P = 3
);
  class C #(
      parameter int K = 1
  );
    static function int k();
      return K;
    endfunction
  endclass
  typedef C#(P) c_t;
  tm_nholder #(.Q(P + 2)) h ();
  initial `checkh(c_t::k(), P);
endmodule

// A typedef of an interface instance with parameters, whose template is visited already with
// its defaults, so left to the instance's turn
interface tm_tdif #(
    parameter int K = 9
);
  typedef logic [K-1:0] t;
endinterface

module tm_tdsink (
    tq_if bus
);
endmodule

module tm_tdholder;
  tm_tdif #(.K(3)) g ();
  typedef g.t g_t;
  localparam int LW = $bits(g_t);
  tq_if #(.W(LW)) b ();
endmodule

module tm_tdmiddle;
  tm_tdsink c (.bus(h.b));
  tm_tdholder h ();
endmodule

// The same through an interface port, into an interface instance in it
interface tm_niif #(
    parameter int W = 3
);
  logic [W-1:0] y;
endinterface

interface tm_nif #(
    parameter int K = 9
);
  tm_niif #(.W(K)) in ();
endinterface

module tm_nholder2 (
    tm_nif s
);
  tq_if #(.W($bits(s.in.y))) b ();
endmodule

module tm_nmiddle (
    tm_nif s
);
  tm_tdsink c (.bus(h.b));
  tm_nholder2 h (.s(s));
endmodule

// Types of expressions
module tm_typeof #(
    parameter int P = 5
);
  localparam logic [P+3:0] Q = 0;
  localparam type(Q) X = 0;
  typedef type(Q) q_t;
  tq_if #(.W($bits(X) + $bits(q_t) - P - 4)) b ();
endmodule

// A type of a class not linked yet, so left to the instance's turn
class tm_tcls #(
    int N = 1
);
  typedef logic [N+3:0] d_t;
endclass

module tm_tclssink (
    tq_if bus
);
endmodule

module tm_tclsdot #(
    parameter int P = 3
);
  typedef tm_tcls#(P) ct;
  localparam ct::d_t B = 0;
  tq_if #(.W($bits(B))) b ();
endmodule

// A value not linked yet, so left to the instance's turn
class tm_cls #(
    int N = 1
);
  localparam int W = N + 4;
endclass

module tm_clssink (
    tq_if bus
);
endmodule

module tm_clsdot #(
    parameter int P = 5
);
  typedef tm_cls#(P) ct;
  localparam int L = ct::W;
  tq_if #(.W(L)) b ();
endmodule

// The same through a typedef, with its own consumer module, as the previous behaviour would
// specialize a shared one for the interface of one of them
module tm_clssink_tdef (
    tq_if bus
);
endmodule

module tm_clsdot_tdef #(
    parameter int P = 3
);
  typedef tm_cls#(P) ct;
  typedef logic [ct::W-1:0] tt;
  localparam int L = $bits(tt);
  tq_if #(.W(L)) b ();
endmodule

module tm_strlen #(
    parameter int P = 4
);
  localparam string S = "abcd";
  tq_if #(.W(S.len() + P)) b ();
endmodule

module tm_twostate #(
    parameter bit [3:0] P = 4'bx101
);
  tq_if #(.W(int'(P))) b ();
endmodule

// A template being visited, already specialized, with a consumer of an instance in it
module tm_sub #(
    parameter int Q = 2
);
  tq_if #(.W(Q)) b ();
endmodule

module tm_visited #(
    parameter int P = 3
);
  typedef logic [P-1:0] w_t;
  tq_chk #(.EXPECT(P + 5)) c (.bus(x.b));
  tm_sub #(.Q($bits(w_t) + 5)) x ();
endmodule

module tm_func #(
    parameter int P = 3
);
  function automatic int f(int x);
    return x + P;
  endfunction
  tq_if #(.W(f(2))) b ();
endmodule

module tm_ranged #(
    parameter logic [3:0] R = 6
);
  tq_if #(.W(int'(R))) b ();
endmodule

module tm_untyped #(
    parameter U = 6
);
  tq_if #(.W(U)) b ();
endmodule

package tm_pkg;
  typedef int w_t;
endpackage

module tm_typed #(
    parameter tm_pkg::w_t V = 6
);
  tq_if #(.W(V)) b ();
endmodule

module tm_enum #(
    parameter int P = 3
);
  typedef enum int {E = P + 5} e_t;
  tq_if #(.W(E)) b ();
endmodule

module tm_typedef #(
    parameter int P = 3
);
  typedef logic [P-1:0] w_t;
  tq_if #(.W($bits(w_t) + 5)) b ();
endmodule

// A type parameter given a type of the module
interface tt_if #(
    parameter type T = logic
);
  T a;
endinterface

module tt_chk #(
    parameter int EXPECT = 1
) (
    tt_if bus
);
  localparam int W = $bits(bus.a);
  if (W != EXPECT) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endmodule

module tm_tpin #(
    parameter int P = 3
);
  typedef logic [P:0] l_t;
  tt_if #(.T(l_t)) b ();
endmodule

// A parameter value of an instance on a path referring to a parameter of another instance
interface tx_if #(
    parameter int W = 7
);
  logic [W-1:0] a;
endinterface

interface tx32_if #(
    parameter int W = 32
);
  logic [W-1:0] a;
endinterface

module tx32_ph #(
    parameter int K = 1
) (
    tx32_if src
);
  tx32_if #(.W(K)) out ();
endmodule

module tx32_sink (
    tx32_if bus
);
endmodule

module tx_ph #(
    parameter int K = 1
) (
    tx_if src
);
  tx_if #(.W(K)) out ();
endmodule

module tx_sink #(
    parameter int EXPECT = 1
) (
    tx_if bus
);
  if ($bits(bus.a) != EXPECT) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endmodule

module tx_values;
  localparam int P = 5;
  localparam int Q = P + 1;
endmodule

module tx_constant;
  tx_values v ();
  tx_if loc ();
  tx_ph #(.K($bits(v.P))) p (.src(loc));
endmodule

module tx_derived;
  tx_values v ();
  tx32_if loc ();
  tx32_ph #(.K($bits(v.Q))) p (.src(loc));
endmodule

// An enum item of an interface port, not specialized yet, in a parameter value of an instance
// on a path, so left to its turn
interface te_if #(
    parameter int W = 3
);
  typedef enum logic [W-1:0] {
    E_A = 1,
    E_B = 2
  } e_t;
  e_t ev;
endinterface

module te_leaf #(
    parameter int K = 0
);
  te_if #(.W(K)) out ();
endmodule

module te_mid (
    te_if p
);
  te_leaf #(.K(p.E_B + 1)) l ();
endmodule

module te_sink (
    te_if bus
);
endmodule

module te_other;
  te_if #(.W(11)) q ();
endmodule

// A parameter of the module being specialized, used with its defaults, in a parameter value of
// an instance on a path
module tc_holder #(
    parameter int K = 1
);
  tx_if #(.W(K)) b ();
endmodule

module tc_top #(
    parameter int P = 15
);
  tx_sink #(.EXPECT(15)) s (.bus(h.b));
  tc_holder #(.K(P)) h ();
endmodule

module sel_ph (
    axi_if src
);
  logic [$bits(src.AWADDR)-1:0] mirror;
  axi_if axi ();
endmodule

module sel_holder;
  axi_if #(
      .ID_W(12),
      .ADDR_W(40)
  ) ifs[2] ();
  sel_ph p (.src(ifs[1]));
endmodule

module mid (
    harness h
);
  // Through an interface port
  bridge #(.EXPECT(68)) dut (.axi(h.axi));
endmodule

bind bind_target harness #(.ADDR_W(20)) h ();

// A type parameter of an instance on a path, whose value is a typedef of the module holding
// it, used with its defaults or specialized
interface tpt_if #(
    parameter int W = 3
);
  logic [W-1:0] a;
endinterface

module tpt_sink (
    tpt_if bus
);
endmodule

module tpt_holder #(
    parameter type T = logic
);
  tpt_if #(.W($bits(T))) b ();
endmodule

module tpt_middle #(
    parameter int K = 2
);
  localparam int KK = K + 1;
  typedef logic [KK-1:0] k_t;
  tpt_holder #(.T(k_t)) h ();
endmodule

// The same with a package's enum item
package tpt_pkg;
  typedef enum int {TPT_E = 4} e_t;
endpackage

module tpt_enum;
  tpt_if #(.W(tpt_pkg::TPT_E + 1)) b ();
endmodule

// A typedef of an interface instance in an interface port, not retargeted yet
interface tpt_niif #(
    parameter int W = 3
);
  typedef logic [W-1:0] y_t;
endinterface

interface tpt_nif #(
    parameter int K = 2
);
  tpt_niif #(.W(K)) in ();
endinterface

module tpt_nholder (
    tpt_nif s
);
  typedef s.in.y_t y_t;
  tpt_if #(.W($bits(y_t))) b ();
endmodule

module tpt_nmiddle (
    tpt_nif s
);
  tpt_sink c (.bus(h.b));
  tpt_nholder h (.s(s));
endmodule

// A reference in an item of another module, through an instance with parameters there, of
// an interface also connected by default to a same-named port of the module searched: not
// approved by that port, so the payload keeps 5 bits, not the default 7, and the sink gets
// 5 + 4, not the default 7
interface nst_in_if #(
    parameter int W = 7,
    parameter logic [W-1:0] DATA = '0
);
endinterface

interface nst_payload_if;
  nst_in_if #(.W(5)) x ();
  localparam int WIDTH = $bits(x.DATA);
  logic [WIDTH-1:0] a;
endinterface

interface nst_out_if #(
    parameter int W = 7
);
  logic [W-1:0] a;
endinterface

module nst_sink (
    nst_out_if bus
);
endmodule

module nst_relay #(
    parameter int K = 1
);
  nst_out_if #(.W(K)) o ();
endmodule

module nst_bridge (
    nst_payload_if p,
    nst_in_if x
);
  nst_relay #(.K($bits(p.a) + 4)) r ();
endmodule

module nst_holder (
    nst_in_if d
);
  nst_payload_if h ();
  nst_bridge b (
      .p(h),
      .x(d)
  );
endmodule

module nst_wrapper (
    nst_in_if d
);
  nst_sink s (.bus(c.b.r.o));
  nst_holder c (.d(d));
endmodule

// A reference through a port of a module of an instance not specialized yet, so still declared
// with the interface's defaults: not approved, so the leaf's localparam is not evaluated in the
// module it was specialized from, and keeps 5 bits, not the default 7
interface hq_in_if #(
    parameter int W = 7
);
endinterface

interface hq_out_if #(
    parameter int W = 7
);
  logic [W-1:0] a;
endinterface

module hq_sink (
    hq_out_if bus
);
endmodule

module hq_relay #(
    parameter int K = 1
);
  hq_out_if #(.W(K)) o ();
endmodule

module hq_leaf (
    hq_in_if x
);
  localparam int LW = x.W;
  logic [LW-1:0] a;
endmodule

module hq_bridge;
  hq_in_if #(.W(5)) i5 ();
  hq_leaf l (.x(i5));
  hq_relay #(.K($bits(l.a) + 2)) r ();
endmodule

module hq_wrapper;
  hq_sink s (.bus(b.r.o));
  hq_bridge b ();
endmodule

module t;
  axi_if #(
      .ID_W(12),
      .ADDR_W(64)
  ) if0 ();  // 12 + 64 + 8 = 84
  axi_if #(
      .ID_W(12),
      .ADDR_W(16)
  ) if1 ();  // 12 + 16 + 8 = 36

  bridge #(.EXPECT(84)) dut0 (.axi(if0));
  bridge #(.EXPECT(36)) dut1 (.axi(if1));
  axi_if #(
      .ID_W(12),
      .ADDR_W(16)
  ) ifs[2] ();
  bridge #(.EXPECT(36)) dut1s (.axi(ifs[1]));

  // Instances of the referenced interfaces are below this module (IEEE 1800-2023 25.3)
  bridge #(.EXPECT(52)) dut2 (.axi(h0.axi));
  harness h0 ();  // 12 + 32 + 8 = 52
  harness #(.ADDR_W(48)) h1 ();  // 12 + 48 + 8 = 68
  bridge #(.EXPECT(68)) dut3 (.axi(h1.axi));
  outer o ();  // 12 + 24 + 8 = 44
  bridge #(.EXPECT(44)) dut4 (.axi(o.h.axi));
  holder m0 ();  // 12 + 40 + 8 = 60
  bridge #(.EXPECT(60)) dut5 (.axi(m0.axi));
  bridge #(.EXPECT(30)) dut6 (.axi(m1.axi));
  holder #(.ADDR_W(10)) m1 ();  // 12 + 10 + 8 = 30
  bridge #(.EXPECT(42)) dut7 (.axi(m2.axi));
  holder m2 ();
  defparam m2.ADDR_W = 22;  // 12 + 22 + 8 = 42
  bind_target b ();  // 12 + 20 + 8 = 40
  bridge #(.EXPECT(40)) dut8 (.axi(b.h.axi));
  mid u_mid (.h(h1));
  bridge #(.EXPECT(36)) dut9 (.axi(p.axi));
  port_holder p (.src(if1));  // 12 + 16 + 8 = 36
  bridge #(.EXPECT(52)) dut10 (.axi(c.p.axi));
  chain_holder c ();  // 12 + 32 + 8 = 52
  // An interface instance, specialized while visiting this module
  wrap_if #(.EXPECT(52)) w (.axi(h0.axi));
  // Rooted at the module's name, so not resolved below it
  bridge #(.EXPECT(84)) dut11 (.axi(t.if0));
  bridge #(.EXPECT(38)) dut14 (.axi(lh.p.axi));
  local_holder #(.ADDR_W(18)) lh ();  // 12 + 18 + 8 = 38
  // Several references through the same instances
  bridge #(.EXPECT(36)) dut13 (.axi(f0.axi));
  fan_holder f0 (.s0(f1.axi), .s1(f1.axi));  // 12 + 16 + 8 = 36
  fan_holder f1 (.s0(f2.axi), .s1(f2.axi));
  fan_holder f2 (.s0(f3.axi), .s1(f3.axi));
  fan_holder f3 (.s0(if1), .s1(if1));
  // Through an interface specialization instantiated more than once
  outer_p #(.ADDR_W(14)) op0 ();  // 12 + 14 + 8 = 34
  outer_p #(.ADDR_W(14)) op1 ();
  mid_outer u_mid_o0 (.o(op0));
  mid_outer u_mid_o1 (.o(op1));
  // A defparam into one of two instances of a module, one connected through the other
  axi_if dpi ();
  dp_holder dp0 (.s(dp1.axi));
  dp_holder dp1 (.s(dpi));
  defparam dp0.l.P = 7;
  initial begin
    `checkh(dp0.l.P, 7);
    `checkh(dp1.l.P, 1);
  end
  // Interface instances specialized while visiting this module, before and after the instance
  // on the path is
  bm_relay bmr (.src(bmy.b));
  bm_width #(.DUMMY(2)) bmw0 (.axi(bmr.axi));
  bm_outer bmy ();
  bm_width #(.DUMMY(3)) bmw1 (.axi(bmr.axi));
  if (bmw1.W != 15) begin : g_bm_bad
    $error("Wrong interface parameters in generate condition");
  end
  // An instance in a generate block declared after a reference to it, shadowing h1
  if (1) begin : g_fwd
    bm_width #(.DUMMY(4)) w (.axi(h1.axi));
    harness h1 ();
    if (w.W != 32) begin : g_bad
      $error("Wrong interface parameters in generate condition");
    end
  end
  // Instances on the path whose specialization is left to their turn
  tp_sink tps (.bus(tp.p.out));
  tp_holder tp ();
  plain_sink shs (.axi(sh.p.axi));
  sel_holder sh ();
  dq_chk dqc (.axi(dq.x.axi));
  dq_chk dqcy (.axi(dq.y.axi));
  dq_chk dns (.axi(dn.x.axi));
  dn_holder dn ();
  dq_chk dnes (.axi(dne.x.axi));
  dn_holder dne ();
  defparam dne.x.V = 30;
  dq_chk dms (.axi(dm1.x.axi));
  dm_holder dm1 ();
  dm_holder #(.EN(0)) dm0 ();
  dq_chk dus (.axi(du.x.axi));
  du_holder du ();
  dq_chk dues (.axi(due.x.axi));
  du_holder due ();
  defparam due.x.V = 30;
  dq_chk dts (.axi(dt.x.axi));
  dt_holder dt ();
  dq_chk dfs (.axi(df.x.axi));
  df_holder df ();
  dl_sink dls (.axi(dl.x.axi));
  dl_holder dl ();
  dq_holder dq ();
  tx_sink #(.EXPECT(32)) txs0 (.bus(tx0.p.out));
  tx_constant tx0 ();
  tx32_sink txs1 (.bus(tx1.p.out));
  tx_derived tx1 ();
  tc_top tct ();
  te_if #(.W(9)) te9 ();
  te_sink tes (.bus(tem.l.out));
  te_other teo ();
  te_mid tem (.p(te9));
  tq_sink tqs0 (.bus(tq0.p.out));
  tq_localparam tq0 ();
  tq_sink tqs1 (.bus(tq1.p.out));
  tq_dtype tq1 ();
  tq_sink tqs2 (.bus(tq2.p.out));
  tq_typedef tq2 ();
  tq_sink tqs3 (.bus(tq3.p.out));
  tq_function tq3 ();
  tq_sink tqs4 (.bus(tq4.p.out));
  tq_twice tq4 ();
  tq_sink tqs5 (.bus(tq5.p.out));
  tq_type tq5 ();
  tq_type #(.T(logic [8:0])) tq6 ();
  tq_chk #(.EXPECT(8)) tms0 (.bus(tm0.b));
  tm_localparam tm0 ();
  tm_localparam #(.P(10)) tm1 ();
  tq_chk #(.EXPECT(8)) tms4 (.bus(tm4.b));
  tm_derived tm4 ();
  tm_derived #(.P(10)) tm5 ();
  tq_chk #(.EXPECT(7)) tmsp (.bus(tmp0.b));
  tm_pkgref tmp0 ();
  tm_pkgref #(.P(10)) tmp1 ();
  tq_chk #(.EXPECT(9)) tmsn (.bus(tmn0.r.out));
  tm_nest tmn0 ();
  tm_nest #(.P(10)) tmn1 ();
  tq_chk #(.EXPECT(5)) tmst0 (.bus(tmt0.b));
  tm_tsize tmt0 ();
  tm_tsize #(.T(logic [8:0])) tmt1 ();
  tq_chk #(.EXPECT(5)) tmsq (.bus(tmq0.b));
  tq_if tmqd ();
  tq_if #(.W(4)) tmqs ();
  tm_port tmq0 (.src(tmqd));
  tm_port #(.P(10)) tmq1 (.src(tmqs));
  tq_chk #(.EXPECT(5)) tmsr (.bus(tmr0.b));
  tm_varsize tmr0 ();
  tm_varsize #(.P(10)) tmr1 ();
  tm_tclssink tmstc (.bus(tmtc0.b));
  tm_tclsdot tmtc0 ();
  tm_tclsdot #(.P(10)) tmtc1 ();
  tq_chk #(.EXPECT(6)) tmsds0 (.bus(tmds0.b));
  tm_dpspec tmds0 ();
  tm_dpspec #(.P(9)) tmds1 ();
  tq_chk #(.EXPECT(10)) tmsds1 (.bus(tmds1.b));
  localparam type tm_enum_t = enum logic [3:0] {TMG = 9};
  localparam tm_enum_t TMY = TMG;
  tq_chk #(.EXPECT(9)) tmspv (.bus(tmpv.b));
  tm_pval #(.P(int'(TMG))) tmpv ();
  tm_rec #(.N(4)) tmrc ();
  tq_chk #(.EXPECT(5)) tmsnc0 (.bus(tmnc0.h.b));
  tm_ncls tmnc0 ();
  tm_ncls #(.P(5)) tmnc1 ();
  tq_chk #(.EXPECT(7)) tmsnc1 (.bus(tmnc1.h.b));
  tm_vif tmvf ();
  tm_vmiddle tmvm (.s(tmvf));
  tm_vsink tmsvn (.bus(tmvh.b));
  tm_vholder tmvh (.s(tmvf2));
  tm_vif tmvf2 ();
  tm_vcmiddle tmvcm ();
  tm_tdif tmtdf ();
  tm_tdmiddle tmtdm ();
  tm_niif tmnidef ();
  tm_nif #(.K(11)) tmnf ();
  tm_nmiddle tmnm (.s(tmnf));
  tq_chk #(.EXPECT(9)) tmsto (.bus(tmto0.b));
  tm_typeof tmto0 ();
  tm_typeof #(.P(9)) tmto1 ();
  tq_chk #(.EXPECT(8)) tmsoe (.bus(tmoe0.b));
  tm_order_enum tmoe0 ();
  tm_order_enum #(.P(10)) tmoe1 ();
  tq_chk #(.EXPECT(8)) tmsov (.bus(tmov0.b));
  tm_order_var tmov0 ();
  tm_order_var #(.P(10)) tmov1 ();
  tm_clssink_tdef tmsct (.bus(tmct0.b));
  tm_clsdot_tdef tmct0 ();
  tm_clsdot_tdef #(.P(10)) tmct1 ();
  tq_chk #(.EXPECT(13)) tmso (.bus(tmo0.b));
  tm_order tmo0 ();
  tm_order #(.P(5)) tmo1 ();
  tm_clssink tmsc (.bus(tmc0.b));
  tm_clsdot tmc0 ();
  tm_clsdot #(.P(8)) tmc1 ();
  tq_chk #(.EXPECT(8)) tmss (.bus(tmz0.b));
  tm_strlen tmz0 ();
  tm_strlen #(.P(10)) tmz1 ();
  tq_chk #(.EXPECT(5)) tmsw (.bus(tmw0.b));
  tm_twostate tmw0 ();
  tm_twostate #(.P(9)) tmw1 ();
  tm_visited #(.P(10)) tmv1 ();
  tm_visited tmv0 ();
  tq_chk #(.EXPECT(5)) tmsf0 (.bus(tmf0.b));
  tm_func tmf0 ();
  tm_func #(.P(10)) tmf1 ();
  tq_chk #(.EXPECT(6)) tms6 (.bus(tm6.b));
  tm_ranged tm6 ();
  tm_ranged #(.R(9)) tm7 ();
  tq_chk #(.EXPECT(6)) tms8 (.bus(tm8.b));
  tm_untyped tm8 ();
  tm_untyped #(.U(12)) tm9 ();
  tq_chk #(.EXPECT(6)) tms10 (.bus(tm10.b));
  tm_typed tm10 ();
  tm_typed #(.V(13)) tm11 ();
  tq_chk #(.EXPECT(8)) tms12 (.bus(tm12.b));
  tm_enum tm12 ();
  tm_enum #(.P(10)) tm13 ();
  tq_chk #(.EXPECT(8)) tms2 (.bus(tm2.b));
  tm_typedef tm2 ();
  tm_typedef #(.P(10)) tm3 ();
  tt_chk #(.EXPECT(4)) tmsy (.bus(tmy0.b));
  tm_tpin tmy0 ();
  tm_tpin #(.P(10)) tmy1 ();
  initial begin
    `checkh($bits(tx0.p.out.a), 32);
    `checkh($bits(tx1.p.out.a), 32);
    `checkh($bits(teo.q.ev), 11);
    `checkh($bits(dq.x.axi.AWADDR), 33);
    `checkh($bits(dq.y.axi.AWADDR), 33);
    `checkh($bits(dq.g_z.z.axi.AWADDR), 32);
    `checkh($bits(dn.x.axi.AWADDR), 33);
    `checkh($bits(dne.x.axi.AWADDR), 33);
    `checkh($bits(dm1.x.axi.AWADDR), 33);
    `checkh($bits(dm0.x.axi.AWADDR), 5);
    `checkh($bits(du.x.axi.AWADDR), 33);
    `checkh($bits(due.x.axi.AWADDR), 33);
    `checkh($bits(dt.x.axi.AWADDR), 33);
    `checkh($bits(df.x.axi.AWADDR), 33);
    `checkh($bits(df.y.a), 11);
    `checkh($bits(tq5.p.out.a), 7);
    `checkh($bits(tq6.p.out.a), 9);
    `checkh($bits(tm0.b.a), 8);
    `checkh($bits(tm1.b.a), 22);
    `checkh($bits(tm2.b.a), 8);
    `checkh($bits(tm3.b.a), 15);
    `checkh($bits(tmy0.b.a), 4);
    `checkh($bits(tmy1.b.a), 11);
    `checkh($bits(tm4.b.a), 8);
    `checkh($bits(tm5.b.a), 15);
    `checkh($bits(tmf0.b.a), 5);
    `checkh($bits(tmc0.b.a), 9);
    `checkh($bits(tmc1.b.a), 12);
    `checkh($bits(tmr0.b.a), 5);
    `checkh($bits(tmr1.b.a), 12);
    `checkh($bits(tmtc0.b.a), 7);
    `checkh($bits(tmtc1.b.a), 14);
    `checkh($bits(tmds0.b.a), 6);
    `checkh($bits(tmds1.b.a), 10);
    `checkh($bits(tmpv.b.a), 9);
    `checkh($bits(tmrc.g.r.b.a), 5);
    `checkh($bits(tmnc1.h.b.a), 7);
    `checkh($bits(tmvm.h.b.a), 9);
    `checkh($bits(tmtdm.h.b.a), 3);
    `checkh($bits(tmvh.b.a), 9);
    `checkh($bits(tmvcm.h.b.a), 9);
    `checkh($bits(tmto0.b.a), 9);
    `checkh($bits(tmto1.b.a), 13);
    `checkh($bits(tmoe0.b.a), 8);
    `checkh($bits(tmoe1.b.a), 15);
    `checkh($bits(tmov0.b.a), 8);
    `checkh($bits(tmov1.b.a), 15);
    `checkh($bits(tmct0.b.a), 7);
    `checkh($bits(tmct1.b.a), 14);
    `checkh($bits(tmo0.b.a), 13);
    `checkh($bits(tmo1.b.a), 15);
    `checkh($bits(tmz0.b.a), 8);
    `checkh($bits(tmz1.b.a), 14);
    `checkh($bits(tmw0.b.a), 5);
    `checkh($bits(tmw1.b.a), 9);
    `checkh($bits(tmv0.x.b.a), 8);
    `checkh($bits(tmv1.x.b.a), 15);
    `checkh($bits(tmq0.b.a), 5);
    `checkh($bits(tmq1.b.a), 12);
    `checkh($bits(tmq1.src.a), 4);
    `checkh($bits(tmt0.b.a), 5);
    `checkh($bits(tmt1.b.a), 9);
    `checkh($bits(tmp0.b.a), 7);
    `checkh($bits(tmp1.b.a), 14);
    `checkh($bits(tmn0.r.out.a), 9);
    `checkh($bits(tmn1.r.out.a), 16);
    `checkh($bits(tmf1.b.a), 12);
    `checkh($bits(tm6.b.a), 6);
    `checkh($bits(tm8.b.a), 6);
    `checkh($bits(tm10.b.a), 6);
    `checkh($bits(tm12.b.a), 8);
    `checkh($bits(tm7.b.a), 9);
    `checkh($bits(tm9.b.a), 12);
    `checkh($bits(tm11.b.a), 13);
    `checkh($bits(tm13.b.a), 15);
    `checkh($bits(tq0.loc.a), 31);
    `checkh($bits(tq1.loc.a), 31);
    `checkh($bits(tq2.loc.a), 31);
    `checkh($bits(tq3.loc.a), 31);
    `checkh($bits(tq4.loc.a), 31);
    `checkh($bits(tq4.p.out.a), 6);
    `checkh($bits(tp.loc.a), 40);
    `checkh($bits(sh.p.mirror), 40);
    `checkh($bits(tpts0.bus.a), 3);
    `checkh($bits(tpts6.bus.a), 7);
    `checkh($bits(tptse.bus.a), 5);
    `checkh($bits(tptnm.c.bus.a), 9);
    `checkh($bits(nstw.c.h.a), 5);
    `checkh($bits(nstw.s.bus.a), 9);
    `checkh($bits(hqw.b.l.a), 5);
  end
  hq_in_if hqd ();
  hq_wrapper hqw ();
  nst_in_if nstd ();
  nst_wrapper nstw (.d(nstd));
  tpt_sink tptse (.bus(tpte.b));
  tpt_enum tpte ();
  tpt_nif #(.K(9)) tptn ();
  tpt_nmiddle tptnm (.s(tptn));
  tpt_sink tpts0 (.bus(tptm0.h.b));
  tpt_middle tptm0 ();
  tpt_sink tpts6 (.bus(tptm6.h.b));
  tpt_middle #(.K(6)) tptm6 ();
  // Instances connected to each other, left to be specialized in their turn
  cycle_holder y0 (.src(y1.axi));
  cycle_holder y1 (.src(y0.axi));
  if (1) begin : g
    harness #(.ADDR_W(30)) h0 ();  // 12 + 30 + 8 = 50
    bridge #(.EXPECT(50)) dut (.axi(h0.axi));
    if (1) begin : g2
      bridge #(.EXPECT(50)) dut (.axi(h0.axi));
    end
    bridge #(.EXPECT(50)) dut_p (.axi(p.axi));
    port_holder p (.src(h0.axi));
  end

  initial begin
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
