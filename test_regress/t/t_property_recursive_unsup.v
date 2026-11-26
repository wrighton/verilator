// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  int cyc = 0;
  logic val = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    val = ~val;
  end

  property check(int n);
    disable iff (n == 0) check(
        n - 1
    );
  endproperty

  assert property (@(posedge clk) check(1))
  else begin
    // Assertion should pass
    $write("*-* Assertion failed *-*\n");
    $stop;
  end


  // Nested recursive instances (#8295)
  property p_self;
    val |-> p_self;
  endproperty

  property p_mutual1;
    val |-> p_mutual2;
  endproperty

  property p_mutual2;
    !val |-> p_mutual1;
  endproperty

  assert property (@(posedge clk) val |-> p_self);
  assert property (@(posedge clk) val |-> p_mutual1);

  // Recursive property, legal unlike a recursive sequence (IEEE 1800-2023 16.12.17)
  sequence s_val;
    val;
  endsequence
  property prop_always(p);
    p and (1'b1 |=> prop_always(p));
  endproperty
  assert property (@(posedge clk) s_val |=> prop_always(val));

  always @(posedge clk) begin
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
