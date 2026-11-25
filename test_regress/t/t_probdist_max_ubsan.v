// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  integer seed;
  integer r;

  initial begin
    // The largest degree of freedom sums 1073741823 exponential draws and returns
    seed = 1;
    r = $dist_chi_square(seed, 2147483647);
    `checkd(r, 2147404011);
    `checkd(seed, -2091305012);

    // The largest k multiplies 2147483647 uniform draws and returns; the
    // product underflows, giving an infinite sample that converts to -2147483648
    seed = 1;
    r = $dist_erlang(seed, 2147483647, 10);
    `checkd(r, -2147483648);
    `checkd(seed, -2147483648);

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
