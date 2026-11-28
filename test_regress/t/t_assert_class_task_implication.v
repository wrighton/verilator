// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An implication of several steps asserted in a task of a class in the scope of a default
// clocking counts like the same assertion outside the class, also for attempts failing together

interface intf (
    input bit clk
);
  int cyc = 0;
  logic a = 0;
  logic b = 1;
  always @(posedge clk) begin
    ++cyc;
    a <= cyc % 4 != 1;
    b <= cyc % 7 != 3;
  end
  default clocking ck @(posedge clk);
  endclocking

  int pass2 = 0;
  int fail2 = 0;
  int fail3 = 0;
  int passNoElse = 0;
  int refPass2 = 0;
  int refFail2 = 0;
  int refFail3 = 0;

  class Checker;
    // Test: two steps, with pass and fail actions
    task check_two();
      assert property (a |-> ##1 b ##1 b) ++pass2;
      else ++fail2;
    endtask
    // Test: three steps, with a fail action
    task check_three();
      assert property (a |-> ##1 b ##1 b ##1 b)
      else ++fail3;
    endtask
    // Test: two steps, without 'else'
    task check_no_else();
      assert property (a |-> ##1 b ##1 b) ++passNoElse;
    endtask
  endclass

  Checker chk = new;

  // The same assertions outside the class
  assert property (a |-> ##1 b ##1 b) ++refPass2;
  else ++refFail2;
  assert property (a |-> ##1 b ##1 b ##1 b)
  else ++refFail3;
endinterface

module sub (
    input bit clk
);
  int cyc = 0;
  logic a = 0;
  logic b = 1;
  always @(posedge clk) begin
    ++cyc;
    a <= cyc % 3 != 2;
    b <= cyc % 5 != 1;
  end
  default clocking ck @(posedge clk);
  endclocking

  int fail2 = 0;
  int refFail2 = 0;

  class Checker;
    // Test: two steps in a class in a module
    task check_two();
      assert property (a |-> ##1 b ##1 b)
      else ++fail2;
    endtask
  endclass

  Checker chk = new;

  assert property (a |-> ##1 b ##1 b)
  else ++refFail2;
endmodule

module t;
  bit clk = 0;
  always #5 clk = ~clk;

  intf i (clk);
  sub s (clk);

  initial begin
    @(posedge clk);
    i.chk.check_two();
    i.chk.check_three();
    i.chk.check_no_else();
    s.chk.check_two();
    repeat (60) @(posedge clk);
    `checkd(i.pass2, i.refPass2);
    `checkd(i.fail2, i.refFail2);
    `checkd(i.fail3, i.refFail3);
    `checkd(i.passNoElse, i.refPass2);
    `checkd(s.fail2, s.refFail2);
    $display("pass2=%0d fail2=%0d fail3=%0d sub fail2=%0d", i.pass2, i.fail2, i.fail3, s.fail2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
