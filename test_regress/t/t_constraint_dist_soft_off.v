// DESCRIPTION: Verilator: A disabled soft DIST leaves the default sampler choice
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); `stop; end while (0);
// verilog_format: on

class SoftOff;
  rand bit [7:0] x, y;
  constraint c_soft {soft x dist {8'd1 := 1, 8'd2 := 1};}
  constraint c_off {disable soft x;}
  constraint c_rel {y == x + 8'd3;}
endclass

module t;
  initial begin
    automatic SoftOff obj = new;
    int ok;
    bit outside;
    outside = 0;
    obj.srandom(29);
    repeat (8) begin
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.y, obj.x + 8'd3);
      outside |= !(obj.x inside {8'd1, 8'd2});
    end
    // The disabled soft constraint no longer restricts x.
    `checkd(outside, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
