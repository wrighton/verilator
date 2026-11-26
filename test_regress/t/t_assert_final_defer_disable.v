// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A disable of a final deferred assertion, or of the outermost scope of its procedure, cancels
// its pending reports (IEEE 1800-2023 16.4.4)
module t;
  int n = 0;
  function automatic void report();
    ++n;
  endfunction
  logic v = 1'b1;
  always @(v) begin : b
    f1 : assert final (v)
    else report();
  end

  logic go_scope = 1'b0;
  always @(go_scope) begin : kill_scope
    disable b;
  end
  logic go_label = 1'b0;
  always @(go_label) begin : kill_label
    disable b.f1;
  end

  initial begin
    #1;
    v = 1'b0;
    go_scope <= 1'b1;
    #1;
    `checkd(n, 0);
    v = 1'b1;
    #1;
    v = 1'b0;
    go_label <= 1'b1;
    #1;
    `checkd(n, 0);
    // Not disabled
    v = 1'b1;
    #1;
    v = 1'b0;
    #1;
    `checkd(n, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
