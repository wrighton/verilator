// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Processes forward messages between two mailboxes forever in zero time, two each way, from two
// messages each that a process puts, which reaches the convergence limit, rather than hanging
// in one resumption of their waiters
module t;
  class Forward;
    mailbox #(int) in;
    mailbox #(int) out;
    task run();
      int v;
      forever begin
        in.get(v);
        out.put(v);
      end
    endtask
  endclass
  mailbox #(int) a = new;
  mailbox #(int) b = new;
  Forward f[4];
  initial begin
    foreach (f[i]) begin
      f[i] = new;
      f[i].in = i % 2 == 1 ? b : a;
      f[i].out = i % 2 == 1 ? a : b;
      fork
        f[i].run();
      join_none
    end
    #1;
    a.put(1);
    b.put(2);
    a.put(3);
    b.put(4);
  end
endmodule
