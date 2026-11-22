// DESCRIPTION: Verilator: Scoped assertion control is not a comb sensitivity
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module child (
    input int value
);
  int immediate_reports;
  int deferred_reports;

  function void record_deferred(input int payload);
    if (payload == 3) deferred_reports++;
  endfunction

  always_comb begin
    check_now : assert (value != 3) else immediate_reports++;
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
    $display("immediate reports=%0d, deferred reports=%0d", a.immediate_reports,
             a.deferred_reports);
    `checkd(a.immediate_reports, 1);
    `checkd(a.deferred_reports, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
