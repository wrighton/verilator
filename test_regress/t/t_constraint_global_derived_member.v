// DESCRIPTION: Verilator: Constraints of a rand member object of a class derived from its holder
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

typedef class mid_t;
typedef class derived_t;

// Test: the constraints of base_t, cloned into base_t for the object of a class derived from it
// reached through rand member objects, are cloned once
class base_t;
  rand bit [6:0] k;
  rand mid_t m;
  constraint c_k {k < 50;}
endclass

class mid_t;
  rand derived_t d;
  rand bit [6:0] j;
  constraint c_j {j > 90;}
endclass

class derived_t extends base_t;
endclass

module t;
  initial begin
    automatic base_t b = new;
    automatic int randomize_result;
    b.m = new;
    b.m.d = new;
    repeat (10) begin
      randomize_result = b.randomize();
      `checkd(randomize_result, 1);
      `checkd(b.k < 50, 1);
      `checkd(b.m.j > 90, 1);
      `checkd(b.m.d.k < 50, 1);
    end

    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
