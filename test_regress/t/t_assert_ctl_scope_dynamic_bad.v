// DESCRIPTION: Dynamic control-type validation for selected and empty scopes.
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-License-Identifier: CC0-1.0
// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on
module assertion_leaf;
  initial begin
    labelled_check: assert (1'b1);
  end
endmodule
module empty_scope;
endmodule
module t;
  assertion_leaf a();
  assertion_leaf b();
  empty_scope e();
  int calls = 0;
  function automatic int bad_effect();
    calls++;
    return 12;
  endfunction
  initial begin
    $assertcontrol(bad_effect(), 2, 1, 0, a, b);
    $assertcontrol(bad_effect(), 4, 1, 0, a);
    $assertcontrol(bad_effect(), 2, 1, 0, e);
    $assertcontrol(bad_effect(), 2, 1);
    `checkd(calls, 4);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
