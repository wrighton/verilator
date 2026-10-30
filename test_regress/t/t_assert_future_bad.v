// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input a,
    input clk
);

  global clocking @(posedge clk);
  endclocking

  assert property (@(posedge clk) 1 == 1)
  else $display("Future=%0d", $future_gclk(a));

  assert property (@(posedge clk) 1 == 1)
  else $display("Future=%0d", $rising_gclk(a));

  assert property (@(posedge clk) 1 == 1)
  else $display("Future=%0d", $falling_gclk(a));

  assert property (@(posedge clk) 1 == 1)
  else $display("Future=%0d", $steady_gclk(a));

  assert property (@(posedge clk) 1 == 1)
  else $display("Future=%0d", $changing_gclk(a));

  // Immediate assertion expressions are not property or sequence expressions
  always @(posedge clk) begin
    assert ($future_gclk(a) == a);
    assume ($rising_gclk(a));
    cover ($falling_gclk(a));
    assert #0 ($steady_gclk(a));
    assert final ($changing_gclk(a));
  end

  // A disable condition is not a property or sequence expression
  assert property (@(posedge clk) disable iff ($future_gclk(a)) a);
  cover property (@(posedge clk) disable iff ($rising_gclk(a)) a);
  assert property (@(posedge clk) disable iff ($falling_gclk(a)) a |-> ##1 a);

  property p_disable;
    @(posedge clk) disable iff ($steady_gclk(a)) a;
  endproperty
  assert property (p_disable);

  sub u_sub (.a(a), .clk(clk));

  initial $stop;

endmodule

module sub (
    input a,
    input clk
);

  global clocking @(posedge clk);
  endclocking

  default disable iff ($changing_gclk(a));

  assert property (@(posedge clk) a);

endmodule
