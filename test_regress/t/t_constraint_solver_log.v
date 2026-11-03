// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Packet;
  rand int one;
  constraint a {one > 0 && one < 2;}
endclass

// Its constraint, its value, and the commands of a solve all exceed a solver I/O buffer
class Long;
  rand bit [19998:0] w;
  constraint c {w != 0;}
endclass

module t;

  Packet p;

  int v;

  initial begin
    p = new;
    v = p.randomize();
    `checkd(v, 1);
    `checkd(p.one, 1);
    begin
      Long l;
      l = new;
      v = l.randomize();
      `checkd(v, 1);
      `checkd(l.w != 0, 1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
