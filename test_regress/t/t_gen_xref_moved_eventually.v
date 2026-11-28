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
// classes, which later passes move out of the block (IEEE 1800-2023 23.8)

module sub #(
    parameter int DIV = 1
);
  logic [7:0] x = 0;
  always @(posedge t.clk) x <= 8'(t.cyc / DIV);
endmodule

// Class in a generate block of a module instantiated more than once
module m #(
    parameter int DIV = 1
);
  for (genvar i = 0; i < 2; ++i) begin : g
    sub #(.DIV(DIV + i)) u ();
    class C;
      function int get();
        return int'(u.x);
      endfunction
    endclass
    C c = new;
  end
endmodule

module t;
  logic clk = 0;
  int cyc = 0;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  for (genvar i = 0; i < 2; ++i) begin : g
    sub #(.DIV(1 + 2 * i)) u ();
    int nevent = 0;
    assert property (@(posedge clk) disable iff (cyc < 2) u.x[0] |-> s_eventually u.x[1])
      nevent++;
    // An attempt passes vacuously, or on the first tick its s_eventually holds
    bit started[$], ah[$], bh[$];
    always @(posedge clk) begin
      started.push_back(cyc >= 2);
      ah.push_back(u.x[0]);
      bh.push_back(u.x[1]);
    end
    function automatic int expPasses();
      int count = 0;
      for (int s = 0; s < ah.size(); ++s) begin
        if (!started[s]) continue;
        if (!ah[s]) begin
          ++count;
          continue;
        end
        for (int e = s; e < bh.size(); ++e) begin
          if (bh[e]) begin
            ++count;
            break;
          end
        end
      end
      return count;
    endfunction
    class Outer;
      class Inner;
        function int get();
          return int'(u.x);
        endfunction
      endclass
    endclass
    Outer::Inner inner = new;
  end

  m #(1) ma ();
  m #(4) mb ();

  initial begin
    #200;
    `checkd(g[0].nevent, g[0].expPasses());
    `checkd(g[1].nevent, g[1].expPasses());
    `checkd(g[0].inner.get(), 19);
    `checkd(g[1].inner.get(), 6);
    `checkd(ma.g[0].c.get(), 19);
    `checkd(ma.g[1].c.get(), 9);
    `checkd(mb.g[0].c.get(), 4);
    `checkd(mb.g[1].c.get(), 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
