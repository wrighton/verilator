// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Types taken from parameterized interface instances, with classes declared before the types and
// before the references, have the widths of the instances' specializations.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifc_typedef #(
    parameter int W = 1
);
  class K;
    int x;
  endclass
  typedef logic [W-1:0] data_t;
endinterface

interface ifc_type #(
    parameter int W = 1
);
  class K;
    int x;
  endclass
  localparam type T = logic [W-1:0];
endinterface

interface ifc_plain #(
    parameter int W = 1
);
  typedef logic [W-1:0] data_t;
endinterface

module t;
  // Test: a typedef of the interface declared after a class there
  ifc_typedef #(.W(5)) a ();
  typedef a.data_t a_t;
  initial begin
    #1;
    `checkd($bits(a_t), 5);
  end

  // Test: a type parameter of the interface declared after a class there
  ifc_type #(.W(7)) b ();
  typedef b.T b_t;
  initial begin
    #1;
    `checkd($bits(b_t), 7);
  end

  // Test: a reference to the interface's typedef after a class declared here
  ifc_plain #(.W(6)) c ();
  class C;
    int x;
  endclass
  typedef c.data_t c_t;
  initial begin
    #1;
    `checkd($bits(c_t), 6);
  end

  initial begin
    #2;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
