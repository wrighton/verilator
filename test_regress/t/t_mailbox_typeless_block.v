// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Blocking methods of typeless mailboxes

// verilator lint_off DECLFILENAME
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); $stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); $stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); $stop; end while(0);

class Item;
  int id;
endclass

// A mailbox subclass passing messages on to the base class
class CountingMbx extends mailbox;
  int puts;
  function new(int bound);
    super.new(bound);
  endfunction
  task put(T message);
    ++puts;
    super.put(message);
  endtask
endclass

class Agent;
  mailbox mb;
  int got[$];
  function new(mailbox mb_arg);
    mb = mb_arg;
  endfunction
  task run(int n);
    repeat (n) begin
      int v;
      mb.get(v);
      got.push_back(v);
    end
  endtask
endclass

module t;
  mailbox m;
  mailbox #() m2;
  std::mailbox m3;

  task automatic produce(mailbox mb, int first, int n);
    for (int i = first; i < first + n; ++i) mb.put(i);
  endtask

  initial begin
    begin : several_types
      int i;
      string s;
      logic [99:0] w;
      Item it;
      m = new;
      i = 5;
      m.put(i);
      s = "hello";
      m.put(s);
      w = 100'h1234_5678_9abc_def0_1234;
      m.put(w);
      it = new;
      it.id = 7;
      m.put(it);
      `checkd(m.num(), 4);
      i = 0;
      m.peek(i);
      `checkd(i, 5);
      i = 0;
      m.get(i);
      `checkd(i, 5);
      s = "";
      m.get(s);
      `checks(s, "hello");
      w = '0;
      m.get(w);
      `checkh(w, 100'h1234_5678_9abc_def0_1234);
      it = null;
      m.peek(it);
      it = null;
      m.get(it);
      `checkd(it.id, 7);
      `checkd(m.num(), 0);
    end
    begin : selected_variables
      int q[$];
      int arr[3];
      Item it;
      m.put(11);
      m.put(12);
      m.put(13);
      q.push_back(0);
      m.get(q[0]);
      m.get(arr[1]);
      it = new;
      m.get(it.id);
      `checkd(q[0], 11);
      `checkd(arr[1], 12);
      `checkd(it.id, 13);
    end
    begin : bounded
      CountingMbx cmbx;
      Agent agent;
      int i;
      // put blocks while full; mailbox passed to a task and a class
      cmbx = new(2);
      m2 = cmbx;
      agent = new(m2);
      fork
        produce(m2, 100, 5);
        begin
          #10;
          `checkd(m2.num(), 2);
          i = 1;
          `checkd(m2.try_put(i), 0);
          agent.run(5);
        end
      join
      `checkd(agent.got.size(), 5);
      foreach (agent.got[k]) `checkd(agent.got[k], 100 + k);
      // put() is not virtual, so only a direct call counts
      `checkd(cmbx.puts, 0);
      i = 9;
      cmbx.put(i);
      `checkd(cmbx.puts, 1);
      i = 0;
      cmbx.get(i);
      `checkd(i, 9);
    end
    begin : std_mailbox
      int i;
      string s;
      m3 = new;
      s = "abc";
      m3.put(s);
      i = 42;
      m3.put(i);
      s = "";
      i = 0;
      m3.get(s);
      m3.get(i);
      `checks(s, "abc");
      `checkd(i, 42);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
