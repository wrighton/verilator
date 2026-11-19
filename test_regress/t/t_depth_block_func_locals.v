// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Blocks nested deeper than --comp-limit-blocks move into new functions, which
// get the arguments and local variables of the function that they reference

module t;
  function automatic int helper(int x);
    int y;
    string s;
    s = $sformatf("%0d", x);
    y = x * 2 + s.len();
    return y;
  endfunction

  function automatic int expect_r(int a, int n);
    int r = 0;
    for (int i = 0; i < n; i++) r = r * 3 + a + 1 + a + i;
    return r;
  endfunction

  class Cls;
    int m_waited;
    // Arguments, locals, an inlined call and a block variable in a deep block
    function int run(int a, output int o);
      int loc = a + 1;
      int r = 0;
      o = 0;
      if (a > 0) begin
        if (a > 1) begin
          if (a > 2) begin
            if (a > 3) begin
              begin
                int z;
                z = a * 7;
                r = r * 3 + loc + a + 0;
                r = r * 3 + loc + a + 1;
                r = r * 3 + loc + a + 2;
                r = r * 3 + loc + a + 3;
                r = r * 3 + loc + a + 4;
                r = r * 3 + loc + a + 5;
                r = r * 3 + loc + a + 6;
                r = r * 3 + loc + a + 7;
                r = r * 3 + loc + a + 8;
                r = r * 3 + loc + a + 9;
                r = r * 3 + loc + a + 10;
                r = r * 3 + loc + a + 11;
                r = r * 3 + loc + a + 12;
                r = r * 3 + loc + a + 13;
                r = r * 3 + loc + a + 14;
                r = r * 3 + loc + a + 15;
                r = r * 3 + loc + a + 16;
                r = r * 3 + loc + a + 17;
                r = r * 3 + loc + a + 18;
                r = r * 3 + loc + a + 19;
                r = r * 3 + loc + a + 20;
                r = r * 3 + loc + a + 21;
                r = r * 3 + loc + a + 22;
                r = r * 3 + loc + a + 23;
                r = r + helper(a) + z;
                o = r + 1;
              end
            end
          end
        end
      end
      return r;
    endfunction
    // A deep block that suspends, with a fork..join using the locals
    task wait_run(int a, ref int acc);
      int loc = a + 1;
      process p = process::self();
      if (a > 0) begin
        if (a > 1) begin
          if (a > 2) begin
            if (a > 3) begin
              fork
                begin
                  #1;
                  acc = acc + loc;
                end
                begin
                  #2;
                  acc = acc * 2;
                end
              join
              acc = acc + helper(a);
              if (p.status() == process::RUNNING) m_waited = m_waited + 1;
            end
          end
        end
      end
    endtask
    // Waiting on an event loops until the event; the test of that loop is deep
    task wait_clk(int a, ref int acc);
      int loc = a + 1;
      if (a > 0) begin
        @(posedge clk);
        acc = acc + loc;
      end
    endtask
    // A deep block that finishes from a fork stays in place
    task finish_run(int a);
      fork
        begin
          if (a > 0) begin
            if (a > 1) begin
              if (a > 2) begin
                $write("*-* All Finished *-*\n");
                $finish;
              end
              else m_waited = 0;
            end
            else m_waited = 1;
          end
          else m_waited = 2;
          m_waited = 99;  // Not reached
        end
      join
    endtask
  endclass

  logic clk = 0;
  always #5 clk = ~clk;

  Cls c_fin = new;
  final `checkd(c_fin.m_waited, 0);

  // Narrow arguments, passed by reference after other arguments
  function automatic int narrow(input bit [1:0] n2, input bit [15:0] n16, input bit [6:0] n7);
    // verilator no_inline_task
    int r = 0;
    if (n2 != 2'h3) begin
      if (n16 != 0) begin
        if (n7 != 0) begin
          r = int'(n2) + int'(n16[11:8]) + int'(n7 + 7'(n16));
        end
      end
    end
    return r;
  endfunction

  // The same in a function of a module
  function automatic int mrun(int a);
    int loc = a + 1;
    int r = 0;
    if (a > 0) begin
      if (a > 1) begin
        if (a > 2) begin
          if (a > 3) begin
            begin
              r = r * 3 + loc + a + 0;
              r = r * 3 + loc + a + 1;
              r = r * 3 + loc + a + 2;
              r = r * 3 + loc + a + 3;
              r = r * 3 + loc + a + 4;
              r = r * 3 + loc + a + 5;
              r = r * 3 + loc + a + 6;
              r = r * 3 + loc + a + 7;
              r = r * 3 + loc + a + 8;
              r = r * 3 + loc + a + 9;
              r = r * 3 + loc + a + 10;
              r = r * 3 + loc + a + 11;
              r = r * 3 + loc + a + 12;
              r = r * 3 + loc + a + 13;
              r = r * 3 + loc + a + 14;
              r = r * 3 + loc + a + 15;
              r = r * 3 + loc + a + 16;
              r = r * 3 + loc + a + 17;
              r = r * 3 + loc + a + 18;
              r = r * 3 + loc + a + 19;
              r = r * 3 + loc + a + 20;
              r = r * 3 + loc + a + 21;
              r = r * 3 + loc + a + 22;
              r = r * 3 + loc + a + 23;
              r = r + helper(a);
            end
          end
        end
      end
    end
    return r;
  endfunction

  initial begin
    automatic Cls c = new;
    automatic int o;
    automatic int acc = 3;
    for (int a = 3; a < 7; a++) begin
      automatic int exp = a > 3 ? expect_r(a, 24) + helper(a) : 0;
      `checkd(c.run(a, o), exp + (a > 3 ? a * 7 : 0));
      `checkd(o, a > 3 ? exp + a * 7 + 1 : 0);
      `checkd(mrun(a), exp);
    end
    for (int i = 0; i < 6; i++) begin
      automatic bit [1:0] n2 = 2'(i);
      automatic bit [15:0] n16 = 16'(i * 4567);
      automatic bit [6:0] n7 = 7'(i * 3 + 1);
      automatic int exp = (n2 != 2'h3 && n16 != 0 && n7 != 0)
          ? int'(n2) + int'(n16[11:8]) + int'(7'(n7 + 7'(n16))) : 0;
      `checkd(narrow(n2, n16, n7), exp);
    end
    c.wait_run(5, acc);
    `checkd(acc, (3 + 6) * 2 + helper(5));
    `checkd(c.m_waited, 1);
    `checkd($time, 2);
    c.wait_clk(5, acc);
    `checkd(acc, (3 + 6) * 2 + helper(5) + 6);
    `checkd($time, 5);
    c_fin.finish_run(acc);
  end
endmodule
