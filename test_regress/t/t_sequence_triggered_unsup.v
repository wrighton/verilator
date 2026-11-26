// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Sequence method 'triggered' on an instance referencing a declaration outside its module,
// generate block or package

interface ifc (
    input clk
);
  logic x = 0;
  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_if;
    @(posedge clk) x;
  endsequence
  // verilog_format: on
endinterface

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

  // Automatic variable in a procedural concurrent assertion
  always @(posedge clk) begin
    for (int k = 0; k < 2; ++k) begin
      assert property (s(d[k]).triggered);
    end
  end
  // verilog_format: on

  // Sequence of an interface instance
  ifc u_if (.clk);
  always @(posedge clk) if (u_if.s_if.triggered) $display("s_if");

  // Method 'matched', formal of the enclosing property
  property p_matched(y);
    @(posedge clk) 1'b1 |-> s(y).matched;
  endproperty
  assert property (p_matched(a));
endmodule
