// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The implicit sensitivity of an always_comb excludes what it, or a function it calls, writes
// (IEEE 1800-2023 9.2.2.2.1), so it does not wake itself. It runs once at time zero and then on a
// change of what it reads (IEEE 1800-2023 9.2.2.2.2).
module t (
    input clk
);
  int cyc = 0;
  bit a = 0;  // Changes on every clock edge
  bit g = 0;  // Changes on every falling clock edge
  bit clk2 = 0;  // Clock of a quarter of the frequency
  bit h = 0;  // Changes on every rising edge of clk2

  // Test: counters incremented by called functions
  int p;
  int n;
  function void bump_p();
    p++;
  endfunction
  function void bump_n();
    n++;
  endfunction
  always_comb
    if (a) bump_p();
    else bump_n();
  int hp;
  function void bump_hp();
    hp++;
  endfunction
  bit hSeen;
  always_comb begin
    hSeen = h;
    bump_hp();
  end
  int hChanges = 0;
  always @(h) hChanges = hChanges + 1;

  // Test: another process drives another element of the variable, which is still a sensitivity
  // verilator lint_off UNOPTFLAT
  bit u[2];
  // verilator lint_on UNOPTFLAT
  bit q;
  always_comb u[0] = g;
  // verilator lint_off ALWCOMBORDER
  always_comb begin
    q = u[0] ^ u[1];
    u[1] = h;
  end
  // verilator lint_on ALWCOMBORDER

  // Test: sensitive to nothing, still runs at time zero
  bit [3:0] s;
  // verilator lint_off ALWCOMBORDER
  always_comb if (s == 0) s = 4'd7;
  // verilator lint_on ALWCOMBORDER

  always @(negedge clk) g <= !g;
  always @(posedge clk2) h <= !h;
  always @(posedge clk) begin
    // One execution at time zero and one per change of a
    `checkd(p, (cyc + 1) / 2);
    `checkd(n, 1 + cyc / 2);
    // One execution at time zero and one per change of h
    `checkd(hp, 1 + hChanges);
    `checkd(hSeen, h);
    `checkd(q, g ^ h);
    `checkd(s, 4'd7);
    cyc <= cyc + 1;
    a <= !a;
    if (cyc % 2 == 1) clk2 <= !clk2;
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
