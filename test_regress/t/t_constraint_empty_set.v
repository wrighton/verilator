// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// IEEE 1800-2023 18.5 constraint_set ::= constraint_expression | { { constraint_expression } }
// so an empty constraint set '{ }' is legal wherever a constraint_set is.
class Cls;
  rand bit [3:0] m;
  rand bit [7:0] x;
  rand bit [7:0] arr[3];

  constraint c_if_else {
    if (m == 1) {
    }
    else {
      x < 10;
    }
  }
  constraint c_if {
    if (m == 2) {}
    -x > 8'hf0;  // Unary operator starting the next constraint
  }
  constraint c_else {
    if (m != 3) x[0] == 1'b0;
    else {}
    &arr[0][1:0] == 1'b0;
  }
  constraint c_foreach {
    foreach (arr[i]) {}
  }
  constraint c_implication {
    (m == 4) -> {}
    (m == 5) -> if (x == 0) {} else {}
    {arr[1][0], arr[2][0]} == 2'b01;
  }
endclass

module t;
  initial begin
    automatic Cls c = new;
    int randomize_result;
    repeat (20) begin
      randomize_result = c.randomize();
      `checkd(randomize_result, 1);
      if (c.m != 1) `checkd(c.x < 10, 1);
      `checkd(c.x > 0 && c.x < 16, 1);
      if (c.m != 3) `checkd(c.x[0], 1'b0);
      `checkd(c.arr[0][1:0] != 2'b11, 1);
      `checkd(c.arr[1][0], 1'b0);
      `checkd(c.arr[2][0], 1'b1);
    end
    // Inline constraint
    repeat (20) begin
      randomize_result = c.randomize() with { if (m == 6) {} else { m == 7; } };
      `checkd(randomize_result, 1);
      `checkd(c.m inside {6, 7}, 1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
