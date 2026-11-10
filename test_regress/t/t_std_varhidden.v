// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// User names matching declarations local to the built-in std package
package p;
  localparam int s = 1;
endpackage

class item;
  rand int x;
endclass

module t;
`ifdef TEST_DECLARE_STD_NAMES
  // User names matching std package classes; this also imports std
  int process;
  int mailbox;
`endif
  item it;
  initial begin
    it = new;
    void'(it.randomize());
`ifdef TEST_DECLARE_STD_NAMES
    process = p::s;
    mailbox = it.x;
    $display("%0d %0d", process, mailbox);
`else
    $display("%0d %0d", p::s, it.x);
`endif
  end
endmodule
