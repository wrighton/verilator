// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package p;
  logic sel;
  logic a0, a1, a2, a3, a4, a5, a6, a7;
  logic b0, b1, b2, b3, b4, b5, b6, b7;
  // Each task awaits its own event and calls itself, so it is not inlined, then calls the next
  task automatic w7(int k);
    if (k > 100) @(posedge (sel ? a7 : b7));
    if (k > 0) w7(k - 1);
  endtask
  task automatic w6(int k);
    if (k > 100) @(posedge (sel ? a6 : b6));
    if (k > 0) w6(k - 1);
    else w7(k + 1);
  endtask
  task automatic w5(int k);
    if (k > 100) @(posedge (sel ? a5 : b5));
    if (k > 0) w5(k - 1);
    else w6(k + 1);
  endtask
  task automatic w4(int k);
    if (k > 100) @(posedge (sel ? a4 : b4));
    if (k > 0) w4(k - 1);
    else w5(k + 1);
  endtask
  task automatic w3(int k);
    if (k > 100) @(posedge (sel ? a3 : b3));
    if (k > 0) w3(k - 1);
    else w4(k + 1);
  endtask
  task automatic w2(int k);
    if (k > 100) @(posedge (sel ? a2 : b2));
    if (k > 0) w2(k - 1);
    else w3(k + 1);
  endtask
  task automatic w1(int k);
    if (k > 100) @(posedge (sel ? a1 : b1));
    if (k > 0) w1(k - 1);
    else w2(k + 1);
  endtask
  task automatic w0(int k);
    if (k > 100) @(posedge (sel ? a0 : b0));
    if (k > 0) w0(k - 1);
    else w1(k + 1);
  endtask
endpackage

module t;
  int x;
  initial begin
    p::w0(1);
    x <= 1;
  end
  initial #1 $display(x);
endmodule
