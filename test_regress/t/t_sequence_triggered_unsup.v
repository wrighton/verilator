// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Sequence method 'triggered' on an instance referencing a non-module-scope declaration

module t (
    input clk
);
  logic a = 0;
  logic [1:0] d = 0;

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s(x);
    @(posedge clk) x;
  endsequence

  // Formal of the enclosing property
  property p(y);
    @(posedge clk) 1'b1 |-> s(y).triggered;
  endproperty
  assert property (p(a));

  // Formal of the enclosing sequence
  sequence s2(z);
    @(posedge clk) s(z).triggered ##1 a;
  endsequence
  cover property (s2(a));

  // Automatic variable
  task automatic wait_triggered(input logic v);
    wait (s(v).triggered);
  endtask
  initial wait_triggered(a);

  for (genvar i = 0; i < 2; ++i) begin : g_loop
    logic v;
    assign v = d[i];
    // Generate block variable
    always @(posedge clk) if (s(v).triggered) $display("v");
    // Genvar
    always @(posedge clk) if (s(d[i]).triggered) $display("d");
    // Generate block sequence
    sequence s_gen;
      @(posedge clk) d[i];
    endsequence
    always @(posedge clk) if (s_gen.triggered) $display("s_gen");
  end
  // verilog_format: on
endmodule
