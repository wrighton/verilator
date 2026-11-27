// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

module t;
  initial begin
    automatic int q[$] = '{1, 2, 3};
    automatic byte bq[$] = '{1, 2, 3};
    automatic int empty[$];
    // An empty array assigned to an empty slice outside the queue changes nothing
    q[5:6] = empty;
    `checkp(q, "'{'h1, 'h2, 'h3}");
    q[-2:-1] = empty;
    `checkp(q, "'{'h1, 'h2, 'h3}");
    // A slice with a bound outside the queue, of another size than assigned, is not written
    q[5:6] = '{9, 9};
    `checkp(q, "'{'h1, 'h2, 'h3}");
    q[1:5] = '{7, 8, 9};
    `checkp(q, "'{'h1, 'h2, 'h3}");
    q[-1:0] = '{4, 5};
    `checkp(q, "'{'h1, 'h2, 'h3}");
    q[1+:4] = '{6};
    `checkp(q, "'{'h1, 'h2, 'h3}");
    q[$-3:$] = '{7, 8, 9, 10};
    `checkp(q, "'{'h1, 'h2, 'h3}");
    bq[2:5] = {>>{32'h04050607}};
    `checkp(bq, "'{'h1, 'h2, 'h3}");
    // Or is written if it is of the same size once limited to the queue
    q[1:5] = '{7, 8};
    `checkp(q, "'{'h1, 'h7, 'h8}");
    q[$-3:$] = '{4, 5, 6};
    `checkp(q, "'{'h4, 'h5, 'h6}");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
