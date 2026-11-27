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
    automatic int q[$] = '{1, 2, 3, 4};
    automatic byte bq[$] = '{1, 2, 3, 4};
    automatic int d[] = '{1, 2, 3, 4};
    automatic int src[$] = '{5, 6, 7};
    if ($test$plusargs("stream")) begin
      // A stream with more elements than the slice
      bq[1:2] = {>>{24'h050607}};
    end
    else if ($test$plusargs("dynamic")) begin
      // A dynamic array slice of constant size assigned an array of another size
      d[1:2] = src;
    end
    else begin
      // A slice inside the queue assigned an array of another size
      q[1:2] = src;
    end
    $display("%p %p %p", q, bq, d);
    `stop;
  end
endmodule
