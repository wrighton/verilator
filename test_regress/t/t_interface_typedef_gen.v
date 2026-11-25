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

// Test: typedef from the instance in a generate block, also in specializations of the module
module m_typedef #(
    parameter int W = 13
);
  if (1) begin : g
    ifc #(.W(W)) b ();
    typedef b.data_t data_t;
    initial begin
      data_t x;
      `checkd($bits(x), W);
      `checkd($bits(data_t), W);
      `checkd($bits(b.data_t), W);
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

module t;
  m_if u_if ();
  m_for u_for ();
  m_hide u_hide ();
  m_named u_named ();
  m_typedef u_typedef ();
  m_typedef #(.W(5)) u_typedef5 ();
  m_typedef #(.W(9)) u_typedef9 ();
  m_cond #(.SEL(0)) u_cond0 ();
  m_cond #(.SEL(1)) u_cond1 ();
  m_array u_array ();

  initial begin
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
