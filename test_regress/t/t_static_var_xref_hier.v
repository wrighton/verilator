// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Static variables of tasks and functions referenced through a hierarchical path

interface ifc;
  function int ifunc(input int b);
    int fv;
    fv = b * 2;
    return fv;
  endfunction
endinterface

module sub;
  task stask(input int a);
    int tv;
    begin : blk
      int bv;
      bv = a + 1;
    end
    tv = a * 3;
  endtask

  initial begin
    #1;
    `checkd(t.tfunc.fv, 70);
  end
endmodule

module t;
  int fv = 77;  // Same name as the static variables

  function int tfunc(input int b);
    int fv;
    fv = b * 10;
    return fv + 1;
  endfunction

  if (1) begin : g
    function int gfunc(input int b);
      int fv;
      fv = b * 4;
      return fv + 1;
    endfunction
  end

  ifc i ();
  sub u ();

  initial begin : ib
    int r;
    r = tfunc(7);
    `checkd(t.tfunc.fv, 70);
    `checkd(tfunc.fv, 70);
    `checkd(fv, 77);
    u.stask(5);
    `checkd(u.stask.tv, 15);
    `checkd(u.stask.blk.bv, 6);
    r = g.gfunc(6);
    `checkd(g.gfunc.fv, 24);
    `checkd(t.g.gfunc.fv, 24);
    r = i.ifunc(4);
    `checkd(i.ifunc.fv, 8);
    #2;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
