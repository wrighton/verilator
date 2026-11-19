// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A task larger than --output-split-cfuncs, with a local that the processes of
// a fork..join keep until the join. At this limit the statements starting the
// processes and the join move into different functions, so the local must stay
// in the task.

class C;
  int m_log[$];
  task run(int k);
    int x;
    fork
      begin
        x = k + 5;
      end
      begin
        #1;
        x = x * 3 + 1;
        m_log.push_back(x);
        #2;
        x = x + 7;
        m_log.push_back(x);
      end
      begin
        #2;
        m_log.push_back(x + 1000);
      end
      begin
        #4;
        m_log.push_back(x + 2000);
        x = x + 1;
      end
      begin
        #5;
        m_log.push_back(x + 3000);
      end
    join
    m_log.push_back(k);
  endtask
endclass

module t;
  // Overwrites the stack while the task waits
  function automatic int deep(int n);
    int arr[64];
    foreach (arr[i]) arr[i] = 32'hdead0000 + i + n;
    return arr[n % 64];
  endfunction

  initial begin
    automatic C c = new;
    automatic int k = 3;
    automatic int x;
    automatic int sum = 0;
    fork
      c.run(k);
    join_none
    for (int i = 0; i < 20; i++) begin
      #0.5;
      sum += deep(i);
    end
    #20;
    x = (k + 5) * 3 + 1;
    `checkd(c.m_log[0], x);
    `checkd(c.m_log[1], x + 1000);
    x = x + 7;
    `checkd(c.m_log[2], x);
    `checkd(c.m_log[3], x + 2000);
    `checkd(c.m_log[4], x + 1 + 3000);
    `checkd(c.m_log[5], k);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
