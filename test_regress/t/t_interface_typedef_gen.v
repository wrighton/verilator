// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Each case is a module of its own, so that no other instance shares its names

interface ifc #(
    parameter int W = 8
) ();
  typedef logic [W-1:0] data_t;
endinterface

interface ifn;
  typedef logic [4:0] data_t;
endinterface

module leaf #(
    parameter type T = logic,
    parameter int EXP = 1
);
  initial `checkd($bits(T), EXP);
endmodule

// Test: type parameter from the typedef of an instance in a generate block
module m_if;
  if (1) begin : g
    ifc #(.W(3)) b ();
    leaf #(.T(b.data_t), .EXP(3)) c ();
  end
endmodule

// Test: each loop iteration uses its own instance
module m_for;
  for (genvar i = 0; i < 2; ++i) begin : g
    ifc #(.W(i + 5)) b ();
    leaf #(.T(b.data_t), .EXP(i + 5)) c ();
  end
endmodule

// Test: an instance in an inner block hides one of the same name outside
module m_hide;
  ifc #(.W(7)) b ();
  if (1) begin : g_outer
    if (1) begin : g_inner
      ifc #(.W(9)) b ();
      leaf #(.T(b.data_t), .EXP(9)) c ();
    end
    leaf #(.T(b.data_t), .EXP(7)) c ();
  end
endmodule

// Test: instance named through its generate block
module m_named;
  if (1) begin : g
    ifc #(.W(11)) b ();
  end
  leaf #(.T(g.b.data_t), .EXP(11)) c ();
endmodule

// Test: typedef from the instance in a generate block
module m_typedef;
  if (1) begin : g
    ifc #(.W(13)) b ();
    typedef b.data_t data_t;
    initial begin
      data_t x;
      `checkd($bits(x), 13);
      `checkd($bits(b.data_t), 13);
    end
  end
endmodule

// Test: if/else and case generate blocks of the same name
module m_cond #(
    parameter int SEL = 0
);
  if (SEL == 0) begin : g
    ifc #(.W(3)) b ();
    leaf #(.T(b.data_t), .EXP(3)) c ();
  end else begin : g
    ifc #(.W(4)) b ();
    leaf #(.T(b.data_t), .EXP(4)) c ();
  end
  case (SEL)
    0: begin : k
      ifc #(.W(5)) b ();
      leaf #(.T(b.data_t), .EXP(5)) c ();
    end
    default: begin : k
      ifc #(.W(6)) b ();
      leaf #(.T(b.data_t), .EXP(6)) c ();
    end
  endcase
  leaf #(.T(g.b.data_t), .EXP(SEL + 3)) c_g ();
  leaf #(.T(k.b.data_t), .EXP(SEL + 5)) c_k ();
endmodule

// Test: elements of an instance array
module m_array;
  ifc #(.W(19)) arr[3] ();
  leaf #(.T(arr[2].data_t), .EXP(19)) c ();
  for (genvar i = 0; i < 2; ++i) begin : g
    leaf #(.T(arr[i].data_t), .EXP(19)) c ();
  end
endmodule

// Test: generate loop blocks selected by number from outside the loop
module m_index;
  for (genvar i = 0; i < 2; ++i) begin : g
    for (genvar j = 0; j < 2; ++j) begin : h
      ifc #(.W(i * 2 + j + 15)) b ();
    end
  end
  leaf #(.T(g[1].h[0].b.data_t), .EXP(17)) c10 ();
  leaf #(.T(g[0].h[1].b.data_t), .EXP(16)) c01 ();
  typedef g[1].h[1].b.data_t data_t;
  initial begin
    data_t x;
    `checkd($bits(x), 18);
    `checkd($bits(g[0].h[0].b.data_t), 15);
  end
endmodule

// Test: descending loop and instance array ranges, and a negative index
module m_range;
  for (genvar i = 3; i >= -1; --i) begin : g
    ifc #(.W(i + 10)) b ();
  end
  leaf #(.T(g[3].b.data_t), .EXP(13)) c3 ();
  leaf #(.T(g[-1].b.data_t), .EXP(9)) cm1 ();
  ifc #(.W(23)) arr[3:1] ();
  leaf #(.T(arr[3].data_t), .EXP(23)) c_arr ();
endmodule

// Test: index given by a parameter, into blocks whose instances are alike
module m_param #(
    parameter int P = 1
);
  for (genvar i = 0; i < 2; ++i) begin : g_dflt
    ifc b ();
  end
  leaf #(.T(g_dflt[P].b.data_t), .EXP(8)) c_dflt ();
  for (genvar i = 0; i < 2; ++i) begin : g_same
    ifc #(.W(21)) b ();
  end
  leaf #(.T(g_same[P].b.data_t), .EXP(21)) c_same ();
  for (genvar i = 0; i < 2; ++i) begin : g_ifn
    ifn b ();
  end
  leaf #(.T(g_ifn[P].b.data_t), .EXP(5)) c_ifn ();
endmodule

// Test: index given by a parameter, into a loop whose blocks do not all have the instance
module m_partial #(
    parameter int P = 2
);
  for (genvar i = 0; i < 3; ++i) begin : g
    if (i != 1) begin : h
      ifc b ();
    end
  end
  leaf #(.T(g[P].h.b.data_t), .EXP(8)) c ();
endmodule

// Test: index in a module specialized more than once
module m_spec #(
    parameter int N = 2
);
  for (genvar i = 0; i < 2; ++i) begin : g
    ifc #(.W(N + i)) b ();
  end
  leaf #(.T(g[1].b.data_t), .EXP(N + 1)) c ();
endmodule

module t;
  m_if u_if ();
  m_for u_for ();
  m_hide u_hide ();
  m_named u_named ();
  m_typedef u_typedef ();
  m_cond #(.SEL(0)) u_cond0 ();
  m_cond #(.SEL(1)) u_cond1 ();
  m_array u_array ();
  m_index u_index ();
  m_range u_range ();
  m_param u_param ();
  m_partial u_partial ();
  m_spec #(.N(2)) u_spec2 ();
  m_spec #(.N(4)) u_spec4 ();

  initial begin
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
