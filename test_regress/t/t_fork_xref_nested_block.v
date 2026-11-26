// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface bus_if;
  int a;
  int n;
  task automatic wr(input int d);
    #1;
    a += d;
    n++;
  endtask
endinterface

module t;
  localparam realtime STEP = 1;
  bus_if m_if ();
  bus_if m_if2 ();

  // Hierarchical references in blocks nested in fork branches, whose statements
  // are moved into a task
  initial begin
    // join_any, a loop's block in a named branch block
    fork
      begin : branch
        for (int i = 0; i < 4; i++) m_if.wr(i);
      end
    join_any
    #(10 * STEP);
    `checkd(m_if.a, 6);
    // join_none, named and loop blocks three levels down, task calls and variables
    fork
      begin : outer
        begin : mid
          for (int i = 1; i <= 2; i++) begin : inner
            int v;
            v = m_if.a;
            m_if.wr(i);
            m_if2.a = v + m_if2.a;
          end
        end
      end
    join_none
    #(10 * STEP);
    `checkd(m_if.a, 9);
    `checkd(m_if2.a, 6 + 7);
    // A branch without begin/end
    fork
      for (int i = 0; i < 3; i++) m_if2.wr(10);
    join_any
    #(10 * STEP);
    `checkd(m_if2.a, 13 + 30);
    // A fork nested in a branch
    fork
      begin : top_branch
        for (int i = 0; i < 2; i++) begin
          fork
            begin : nested_branch
              for (int j = 0; j < 2; j++) m_if.wr(100);
            end
          join_none
        end
        #(5 * STEP);
        m_if2.n = m_if.n;
      end
    join_any
    #(10 * STEP);
    `checkd(m_if.a, 409);
    `checkd(m_if2.n, 6 + 4);
    // Blocks of the same name nested, and two forks nested in one branch, one with
    // a branch block of the name of the outer branch block
    fork
      begin : rep
        begin : rep
          for (int i = 0; i < 2; i++) m_if.wr(1000);
        end
        fork
          begin : first
            for (int j = 0; j < 2; j++) m_if2.wr(1);
          end
        join_none
        begin : again
          for (int i = 0; i < 1; i++) begin
            fork
              begin : rep
                for (int j = 0; j < 3; j++) m_if2.wr(2);
              end
            join_none
          end
        end
      end
    join_any
    #(10 * STEP);
    `checkd(m_if.a, 2409);
    `checkd(m_if2.a, 43 + 2 + 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
