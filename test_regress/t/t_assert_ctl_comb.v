// DESCRIPTION: Verilator: Scoped assertion control is not a comb sensitivity
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module child (
    input int value
);
  function void record_deferred(input int payload);
    $display("deferred assertion report: %0d", payload);
  endfunction

  always_comb begin
    check_now : assert (value != 3) else $display("immediate assertion report: %0d", value);
  end

  always_comb begin
    check_later : assert #0 (value != 3) else record_deferred(value);
  end
endmodule

module t;
  bit clk;
  int value;
  child a (.value);

  always #5 clk = ~clk;
  always @(posedge clk) value <= value + 1;

  initial begin
`ifdef GLOBAL_CONTROL
    $assertoff;
    $asserton;
`else
    $assertoff(0, a);
    $asserton(0, a);
`endif
    #2;
    #80;
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
