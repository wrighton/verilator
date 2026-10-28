// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Hierarchical references relative to a generate block, from s_eventually and
// a nested class, which later passes move out of the block (IEEE 1800-2023 23.8)

module sub #(
    parameter int ID = 0
);
  logic [7:0] x = 0;
  always @(posedge t.clk) x <= (ID == 0) ? 8'(t.cyc) : 8'(t.cyc / 3);
endmodule

module t;
  logic clk = 0;
  int cyc = 0;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  for (genvar i = 0; i < 2; ++i) begin : g
    sub #(.ID(i)) u ();
    int nevent = 0;
    int nevent_exp = 0;
    assert property (@(posedge clk) disable iff (cyc < 2) u.x[0] |-> s_eventually u.x[1])
      nevent++;
    always @(posedge clk) if (cyc >= 2 && !u.x[0]) nevent_exp++;  // Vacuous passes
    class Outer;
      class Inner;
        function int get();
          return int'(u.x);
        endfunction
      endclass
    endclass
    Outer::Inner inner = new;
  end

  initial begin
    #200;
    // Only vacuous passes are counted before the end of simulation
    `checkd(g[0].nevent, g[0].nevent_exp);
    `checkd(g[1].nevent, g[1].nevent_exp);
    `checkd(g[0].inner.get(), 19);
    `checkd(g[1].inner.get(), 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
