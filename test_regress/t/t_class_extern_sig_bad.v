// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  extern function void ftask_bad();  //<--- Error (function vs task)
  extern task tfunc_bad();  //<--- Error (task vs function)
  extern function int fdir_bad(input int a, output int b);  //<--- Error (direction)
  extern task tdir_bad(ref int a, const ref int b);  //<--- Error (direction)
  extern function void fdir_ok(input int a, output int b, inout int c, ref int d);
endclass

task Cls::ftask_bad();
endtask

function void Cls::tfunc_bad();
endfunction

function int Cls::fdir_bad(output int a, output int b);
  return 0;
endfunction

task Cls::tdir_bad(const ref int a, const ref int b);
endtask

function void Cls::fdir_ok(input int a, output int b, inout int c, ref int d);
  int local_var;
endfunction

module t;
  initial $stop;
endmodule
