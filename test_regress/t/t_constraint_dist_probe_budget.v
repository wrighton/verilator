// DESCRIPTION: Verilator: Keep the satisfying DIST model when rejected probes exhaust checks
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); `stop; end while (0);
`define IMPOSSIBLE(n) (9'(n)) := 12'hfff
`define SIXTEEN(n) \
  `IMPOSSIBLE(n+0),  `IMPOSSIBLE(n+1),  `IMPOSSIBLE(n+2),  `IMPOSSIBLE(n+3), \
  `IMPOSSIBLE(n+4),  `IMPOSSIBLE(n+5),  `IMPOSSIBLE(n+6),  `IMPOSSIBLE(n+7), \
  `IMPOSSIBLE(n+8),  `IMPOSSIBLE(n+9),  `IMPOSSIBLE(n+10), `IMPOSSIBLE(n+11), \
  `IMPOSSIBLE(n+12), `IMPOSSIBLE(n+13), `IMPOSSIBLE(n+14), `IMPOSSIBLE(n+15)
// verilog_format: on

class ProbeBudget;
  rand bit [8:0] pick, offset;
  rand bit [7:0] free_value;
  constraint c {
    pick == 9'd0;
    offset == 9'd0;
    free_value inside {[8'd5:8'd150]};
    (pick + offset) dist {
      `SIXTEEN(1),   `SIXTEEN(17),  `SIXTEEN(33),  `SIXTEEN(49),
      `SIXTEEN(65),  `SIXTEEN(81),  `SIXTEEN(97),  `SIXTEEN(113),
      `SIXTEEN(129), `SIXTEEN(145), `SIXTEEN(161), `SIXTEEN(177),
      `SIXTEEN(193), `SIXTEEN(209), `SIXTEEN(225), `SIXTEEN(241),
      `SIXTEEN(257), 9'd0 := 12'd1
    };
  }
endclass

module t;
  initial begin
    automatic ProbeBudget obj = new;
    int ok;
    obj.srandom(233);
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.pick, 9'd0);
    `checkd((obj.free_value inside {[8'd5:8'd150]}), 1'b1);
    $display("Probe-budget value %0d", obj.free_value);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
