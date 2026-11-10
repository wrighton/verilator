// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  logic v, r;
  int count_direct = 0;
  int count_nested = 0;
  int count_inline = 0;

  property p_lv;
    logic x;
    (v, x = r) |-> x;
  endproperty

  property p_outer;
    p_lv;
  endproperty

  // The same property local variable through a direct and a nested instance
  assert property (@(posedge clk) p_lv)
  else count_direct <= count_direct + 1;

  assert property (@(posedge clk) p_outer)
  else count_nested <= count_nested + 1;

  assert property (@(posedge clk) v |-> r)
  else count_inline <= count_inline + 1;

  // Another property with a local variable of the same name and type, instanced in a property
  // expression
  int count_other = 0;
  property p_other;
    logic x;
    (r, x = v) |-> x;
  endproperty

  assert property (@(posedge clk) cyc > 0 |-> p_other)
  else count_other <= count_other + 1;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    v <= cyc[0];
    r <= cyc[1];
    if (cyc == 20) begin
      `checkd(count_direct, count_inline);
      `checkd(count_nested, count_inline);
      `checkd(count_inline, 5);
      `checkd(count_other, 5);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
