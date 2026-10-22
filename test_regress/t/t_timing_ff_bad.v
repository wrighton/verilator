// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  logic clk = 0;
  logic d = 0;
  logic q1, q2, q3, q4, q5, q6, q7, q8, q9;

  always_ff @(posedge clk) begin
    q1 <= d;
    @(posedge clk) q1 <= ~d;  // <--- Bad
  end
  always_ff @(posedge clk) begin
    #1 q2 <= d;  // <--- Bad
  end
  always_ff @(posedge clk) begin
    wait (d) q3 <= d;  // <--- Bad
  end
  always_ff @(posedge clk) begin
    q4 = #1 d;  // <--- Bad
  end
  always_ff @(posedge clk) begin
    q5 = @(negedge clk) d;  // <--- Bad
  end
  always_ff @(posedge clk) @(negedge clk) q6 <= d;  // <--- Bad
  default clocking @(posedge clk);
  endclocking
  always_ff @(posedge clk) begin
    ##1;  // <--- Bad
    // Cycle delay in a property is legal, but unsupported
    assert property (d ##1 d);
  end

  // Legal
  always_ff @(posedge clk) begin
    logic tmp;
    tmp = d;
    q7 <= #1 tmp;
    fork
      #1 q8 <= d;
    join_none
  end
  always_ff begin
    @(posedge clk) q9 <= d;
  end

endmodule
