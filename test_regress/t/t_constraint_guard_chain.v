// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class ChainNode;
  ChainNode next;
  bit flag;
endclass

class ChainGuard;
  ChainNode head;
  rand bit [6:0] value;
  constraint c {
    if ((head.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.next.flag == 1) && (head != null))
    value == 7'd23;
  }
endclass

module t;
  initial begin
    automatic ChainGuard g = new;
    ChainNode nodes[33];
    int res;
    foreach (nodes[i]) nodes[i] = new;
    for (int i = 0; i < 32; ++i) nodes[i].next = nodes[i+1];
    repeat (10) begin
      g.head = null;
      res = g.randomize();
      `checkd(res, 1);
      g.head = nodes[0];
      nodes[32].flag = 1;
      res = g.randomize();
      `checkd(res, 1);
      `checkd(g.value, 7'd23);
      nodes[32].flag = 0;
      res = g.randomize() with {value == 7'd9;};
      `checkd(res, 1);
      nodes[16].next = null;
      res = g.randomize();
      `checkd(res, 0);
      nodes[16].next = nodes[17];
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
