// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Parameterized classes referencing each other through their base class parameters form a
// cycle in the hierarchy of specializations. The levels given to the classes in such a cycle
// must not depend on memory layout. The six specializations below are alternately rooted at
// 'mon' and 'drv'; with the parents of each class visited in the order they are found, the
// mirrored classes get identical levels.

interface ifc #(int W = 1);
  logic [W-1:0] d;
endinterface

class base #(type VIF = int, type PEER = int);
  VIF vif;
  PEER peer;
endclass

typedef class drv;

class mon #(int W = 1) extends base #(virtual ifc #(W), drv #(W));
  function int width();
    return W;
  endfunction
endclass

class drv #(int W = 1) extends base #(virtual ifc #(W), mon #(W));
  function int width();
    return W + 100;
  endfunction
endclass

module t;
  ifc #(2) i2 ();
  ifc #(3) i3 ();
  ifc #(5) i5 ();
  ifc #(6) i6 ();
  ifc #(7) i7 ();
  ifc #(9) i9 ();

  initial begin
    mon #(2) m2;
    drv #(3) d3;
    mon #(5) m5;
    drv #(6) d6;
    mon #(7) m7;
    drv #(9) d9;
    m2 = new;
    d3 = new;
    m5 = new;
    d6 = new;
    m7 = new;
    d9 = new;
    m2.vif = i2;
    d3.vif = i3;
    m5.vif = i5;
    d6.vif = i6;
    m7.vif = i7;
    d9.vif = i9;
    `checkd(m2.width(), 2);
    `checkd(d3.width(), 103);
    `checkd(m5.width(), 5);
    `checkd(d6.width(), 106);
    `checkd(m7.width(), 7);
    `checkd(d9.width(), 109);
    m2.vif.d = 2'h1;
    `checkd(i2.d, 2'h1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
