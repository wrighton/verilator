// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Final deferred assertions, assumptions and covers in a module with no initial or always
// procedure (IEEE 1800-2023 16.4). The cover runs with --coverage-user, as EXP_COVERS says.
module t;
  logic a = 1'b1;
  int fails = 0;
  int covers = 0;
  function automatic void fail();
    ++fails;
  endfunction
  function automatic void hit();
    ++covers;
  endfunction
  af : assert final (a)
  else fail();
  am : assume final (a)
  else fail();
  cf : cover final (a) hit();
  final begin
    `checkd(fails, 0);
    `checkd(covers, `EXP_COVERS);
    $write("*-* All Finished *-*\n");
  end
endmodule
