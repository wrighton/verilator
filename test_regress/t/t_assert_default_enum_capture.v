// DESCRIPTION: Verilator: Pure enum default capture in a concurrent assertion
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
// verilog_format: on

module t;
  typedef enum bit [6:0] {IDLE = 7'd1, BUSY = 7'd65} state_t;
  bit clk = 0;
  bit selected = 0;
  always #1 clk = !clk;

  // Assertion functions have inputs only and no side effects (IEEE 1800-2023 16.6).
  function automatic state_t selected_enum();
    return selected ? BUSY : IDLE;
  endfunction
  function automatic string render(input string value = $sformatf("%p", selected_enum()));
    return value;
  endfunction

  assert property (@(posedge clk) render() == (selected ? "BUSY" : "IDLE")) else `stop;

  initial begin
    for (int i = 0; i < 32; ++i) begin
      // Hold inputs stable through assertion sampling and evaluation.
      @(negedge clk);
      selected = !selected;
      @(posedge clk);
      #1;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
