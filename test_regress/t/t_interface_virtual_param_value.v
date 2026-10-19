// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A typed parameter takes the value of its override converted to its type
// (IEEE 1800-2017 6.20.2), and interfaces whose parameters have equal values
// and types are of the same type (IEEE 1800-2017 25.9), however the override
// value is written.

interface ifc #(
    parameter bit B = 0,
    parameter logic [3:0] N = 0
);
  logic x;
endinterface

class Holder #(
    bit B = 0
);
  typedef virtual ifc #(.B(B)) vif_t;
  vif_t vif;
endclass

module t;
  ifc #(.B(1)) b_int ();
  ifc #(.B(1'b1)) b_bit ();
  ifc #(.B('1)) b_fill ();
  ifc #(.B(1'sb1)) b_signed ();
  ifc #(.N('1)) n_fill ();
  ifc #(.N(4'sb1111)) n_signed ();

  virtual ifc #(.B(1)) vb_int;
  virtual ifc #(.B('1)) vb_fill;
  virtual ifc #(.B(1'sb1)) vb_signed;
  virtual ifc #(.N(4'hf)) vn_hex;
  Holder #(1) h_int;
  Holder #('1) h_fill;

  initial begin
    vb_int = b_bit;
    vb_int = b_fill;
    vb_int = b_signed;
    vb_fill = b_int;
    vb_signed = b_int;
    vb_fill = vb_signed;
    `checkh(vb_fill.B, 1'b1);
    vn_hex = n_fill;
    vn_hex = n_signed;
    `checkh(vn_hex.N, 4'hf);
    h_int = new;
    h_fill = new;
    h_int.vif = b_fill;
    h_fill.vif = b_int;
    h_int.vif = h_fill.vif;
    `checkh(h_int.vif.B, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
