// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A violated unique or unique0 if still executes the statement of the first true condition
// (IEEE 1800-2023 12.4.2)
module t;
  initial begin
    logic [6:0] v;
    int n;
    v = 7'd5;

    // Overlap
    n = 0;
    unique if (v > 7'd1) n = 1;
    else if (v > 7'd2) n = 2;
    `checkd(n, 1);

    n = 0;
    unique0 if (v > 7'd1) n = 1;
    else if (v > 7'd2) n = 2;
    `checkd(n, 1);

    // Overlap of later conditions
    n = 0;
    unique if (v == 7'd1) n = 1;
    else if (v > 7'd2) n = 2;
    else if (v > 7'd3) n = 3;
    else n = 4;
    `checkd(n, 2);

    // No match without an else executes nothing
    n = 0;
    unique if (v == 7'd1) n = 1;
    else if (v == 7'd2) n = 2;
    `checkd(n, 0);

    // A priority if executes the first true condition
    n = 0;
    priority if (v > 7'd1) n = 1;
    else if (v > 7'd2) n = 2;
    `checkd(n, 1);

    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
