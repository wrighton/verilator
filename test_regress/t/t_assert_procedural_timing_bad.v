// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// No clock is inferred for a procedure with a blocking timing control or another event control,
// so without default clocking its concurrent assertions and sampled value functions have no
// clock (IEEE 1800-2023 16.14.6, 16.16)
module sub (
    input clk,
    input a
);
  default clocking @(posedge clk);
  endclocking
  logic x;
  // Default clocking applies, with the same event
  always @(posedge clk) begin
    #1;
    if ($rose(a)) x = 1;
  end
endmodule

module t (
    input clk,
    input a,
    input b
);
  logic x, y;
  task automatic wait_clk();
    @(posedge clk);
  endtask
  task automatic spawn();
    fork
      #1 y = 1;
    join_none
    y <= @(negedge clk) a;
  endtask
  task automatic recurse(int n);
    if (n > 0) recurse(n - 1);
  endtask

  sub u_sub (.*);

  always @(posedge clk) begin
    #1;
    assert property (a);
    assert property (b);
  end
  always @(posedge clk) begin
    wait (b);
    if ($rose(a)) x = 1;
  end
  always @(posedge clk) begin
    fork
      x = 0;
      y = 0;
    join
    assert property (a);
  end
  always @(posedge clk) begin
    wait_clk();
    assert property (a);
  end
  always @(negedge clk) begin
    wait_clk();
    assert property (a);
  end
  always @(posedge clk) begin
    fork
      @(negedge clk) x = 1;
    join_none
    assert property (a);
  end
  always @(posedge clk) begin
    x <= @(negedge clk) a;
    assert property (a);
  end
  // Not blocking
  always @(posedge clk) begin
    fork
      #1 x = 1;
    join_none
    x <= #1 a;
    spawn();
    recurse(2);
    assert property (a);
  end
endmodule
