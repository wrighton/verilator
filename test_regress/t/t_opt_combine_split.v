// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

string order_q[$];
int unsigned calls = 0;

class registry;
  // Impure, so each call must happen once per instance
  static function bit is_disabled(string name);
    ++calls;
    return $test$plusargs(name);
  endfunction
endclass

// The initial, static and final code of the instances is split into several
// functions (--output-split-cfuncs), which are shared by all instances
module sub;
  /* verilator no_inline_module */
  string static_name = $sformatf("%m");
  logic dis_a;
  logic dis_b;
  // Constant inputs, so these become initial code
  assign dis_a = registry::is_disabled("dis_a");
  assign dis_b = registry::is_disabled("dis_b");
  string init_name;
  initial begin
    init_name = $sformatf("%m");
    order_q.push_back(init_name);
    $display("initial %m");
  end
  initial begin
    #1;
    $display("resumed %m");
    $display("resumed again %m");
  end
  final $display("final %m dis_a=%0d dis_b=%0d", dis_a, dis_b);
endmodule

module t;
  sub u1 ();
  sub u2 ();
  sub u3 ();
  // An identical part of a process that needs a VlProcess is not shared with this one
  initial begin
    #2;
    $display("same");
    $display("parts");
  end
  initial begin
    fork
      #3;
    join_none
    wait fork;
    $display("same");
    $display("parts");
  end
  initial begin
    #5;
    `checks(u1.static_name, "t.u1");
    `checks(u2.static_name, "t.u2");
    `checks(u3.static_name, "t.u3");
    `checks(u1.init_name, "t.u1");
    `checks(u2.init_name, "t.u2");
    `checks(u3.init_name, "t.u3");
    `checkd(order_q.size(), 3);
    `checks(order_q[0], "t.u1");
    `checks(order_q[1], "t.u2");
    `checks(order_q[2], "t.u3");
    `checkd(calls, 6);
    `checkd(u1.dis_a, 1'b0);
    `checkd(u2.dis_b, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
