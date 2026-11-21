// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Uses of mailboxes that reach no member internal to them: a user class named as the mailbox of
// the std package, with members named as its waiting queues, is an ordinary class, and type
// queries of public methods of mailboxes of several types widen their bodies, which use them
package p;
  class mailbox #(
      type T = int
  );
    local chandle m_getQueue;
    local chandle m_putQueue;
    function bit idle();
      return m_getQueue == null && m_putQueue == null;
    endfunction
  endclass
endpackage

class Holder #(
    type T = int
);
  T value;
endclass

module t;
  mailbox #(int) mi = new;
  mailbox #(string) ms = new;
  mailbox #(byte) mb = new;
  localparam type num_t = type(mi.num());
  num_t n;
  Holder #(type(ms.num())) h = new;
  initial begin
    p::mailbox #(int) m;
    byte v;
    m = new;
    `checkd(m.idle(), 1'b1);
    void'(mb.try_put(8'd5));
    `checkd(mb.try_peek(v), 1);
    n = mi.num();
    h.value = ms.num() + mb.num();
    `checkd($bits(n), 32);
    `checkd(h.value, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
