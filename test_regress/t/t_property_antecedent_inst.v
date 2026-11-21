// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A property instance whose body is a boolean, as an implication antecedent

module t (
    input clk
);
  int cyc = 0;
  logic a = 0, b = 0;
  int fail_bool = 0, fail_lnot = 0, fail_func = 0;
  int fail_bool_inline = 0, fail_lnot_inline = 0;

  function automatic logic inv(logic x);
    return !x;
  endfunction

  property p_bool;
    a;
  endproperty
  property p_lnot;
    !a;
  endproperty
  property p_func;
    inv(a);
  endproperty

  assert property (@(posedge clk) p_bool |-> b)
  else fail_bool++;
  assert property (@(posedge clk) a |-> b)
  else fail_bool_inline++;
  assert property (@(posedge clk) p_lnot |-> b)
  else fail_lnot++;
  assert property (@(posedge clk) !a |-> b)
  else fail_lnot_inline++;
  assert property (@(posedge clk) p_func |-> b)
  else fail_func++;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    a <= cyc[0] ^ cyc[2];
    b <= cyc[1];
    if (cyc == 40) begin
      `checkd(fail_bool, fail_bool_inline);
      `checkd(fail_lnot, fail_lnot_inline);
      `checkd(fail_func, fail_lnot_inline);
      `checkd(fail_bool, 10);
      `checkd(fail_lnot, 11);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
