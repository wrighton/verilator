// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The sampled value of a const cast is the current value of its expression, and so is its past
// value (IEEE 1800-2023 16.5.1)
module t;
  bit clk = 0;
  // A blocking write in the time step of each edge, before it, so at each tick the current value
  // of x is its sampled value plus 3
  bit [6:0] x = 0;
  initial begin
    repeat (8) begin
      #4 x = x + 7'd3;
      clk = 1;
      #1 clk = 0;
    end
    #5;
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // Test: sampled value functions in a procedure
  bit [6:0] y = 0;
  bit [6:0] z = 0;
  bit [6:0] zp = 0;  // The previous sampled value of z
  bit b = 0;
  always @(posedge clk) begin
    y = y + 7'd5;  // The current value differs from the sampled value
    `checkd($past(const'(y)), y);
    `checkd($sampled(const'(y)), y);
    `checkd($stable(const'(y)), 1'b1);
    `checkd($changed(const'(y)), 1'b0);
    `checkd($rose(const'(y[0])), 1'b0);
    `checkd($fell(const'(y[0])), 1'b0);
    `checkd($past(const'(7'd5)), 7'd5);
    // Only the operand outside the cast has a past value
    `checkd($past(const'(y) + z), y + zp);
    // Also with a constant current value
    b = 1'b1;
    `checkd($sampled(const'(b)), 1'b1);
  end
  always @(posedge clk) begin
    z <= z + 7'd1;
    zp <= z;
  end

  // Test: concurrent assertions
  int npass1 = 0;
  int npass2 = 0;
  int npass3 = 0;
  int npass4 = 0;
  int npass5 = 0;
  a1 :
  assert property (@(posedge clk) const'(x) == x + 7'd3) ++npass1;
  a2 :
  assert property (@(posedge clk) $past(const'(x)) == const'(x)) ++npass2;
  a3 :
  assert property (@(posedge clk) $stable(const'(x)) && !$changed(const'(x))) ++npass3;
  a4 :
  assert property (@(posedge clk) $sampled(const'(x)) == x + 7'd3) ++npass4;
  a5 :
  assert property (@(posedge clk) 1 |-> ##1 const'(x) == x + 7'd3) ++npass5;

  // Test: procedural concurrent assertion, with the value when queued (IEEE 1800-2023 16.14.6.1)
  int npass6 = 0;
  always @(posedge clk) begin
    a6 : assert property (const'(x) == x + 7'd3) ++npass6;
  end

  final begin
    `checkd(npass1, 8);
    `checkd(npass2, 8);
    `checkd(npass3, 8);
    `checkd(npass4, 8);
    `checkd(npass5, 7);
    `checkd(npass6, 8);
  end
endmodule
