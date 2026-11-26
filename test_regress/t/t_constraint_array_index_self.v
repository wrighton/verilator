// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An element select of an array whose index reads the same array, as a whole or by a random
// index, also through another such select

class Self;
  rand bit [15:0] tbl[];
  rand bit [15:0] que[$];
  rand int unsigned j;
  rand bit [15:0] s, n, nn, q;
  constraint c {
    j < 4;
    s == tbl[(tbl.sum() with (int'(item))) % 4];
    n == tbl[tbl[j] % 4];
    nn == tbl[tbl[tbl[j] % 4] % 4];
    q == que[que[j] % 4];
  }
  function new();
    tbl = new[4];
    foreach (tbl[i]) tbl[i] = 16'(i + 1);
    que = '{16'd7, 16'd2, 16'd5, 16'd0};
  endfunction
endclass

module t;
  initial begin
    automatic Self o = new;
    automatic bit [15:0] saved[] = o.tbl;
    automatic int ok;
    // Held, so read as state
    o.tbl.rand_mode(0);
    o.que.rand_mode(0);
    repeat (8) begin
      ok = o.randomize();
      `checkh(ok, 1);
      `checkh(o.tbl == saved, 1'b1);
      `checkh(o.s, o.tbl[10 % 4]);
      `checkh(o.n, o.tbl[o.tbl[o.j] % 4]);
      `checkh(o.nn, o.tbl[o.tbl[o.tbl[o.j] % 4] % 4]);
      `checkh(o.q, o.que[o.que[o.j] % 4]);
    end
    // Solved with the reads
    o.tbl.rand_mode(1);
    o.que.rand_mode(1);
    repeat (4) begin
      ok = o.randomize() with {
        tbl.size() == 4;
        que.size() == 4;
      };
      `checkh(ok, 1);
      `checkh(o.s, o.tbl[(o.tbl.sum() with (int'(item))) % 4]);
      `checkh(o.n, o.tbl[o.tbl[o.j] % 4]);
      `checkh(o.nn, o.tbl[o.tbl[o.tbl[o.j] % 4] % 4]);
      `checkh(o.q, o.que[o.que[o.j] % 4]);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
