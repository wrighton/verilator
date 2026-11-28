// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Continuous streaming assignments of queues, written or as port connections: a warning once the
// stream does not fit, whose result is not checked

module sub_in (
    input bit [31:0] i
);
endmodule

module sub_out (
    output bit [11:0] o
);
  assign o = 12'h5dc;
endmodule

module t;
  byte q[$];
  byte oq[$];
  int j;
  assign j = {>>{q}};
  sub_in u_in (.i({>>{q}}));
  sub_out u_out (.o({>>{oq}}));

  initial begin
    q = '{8'h01, 8'h02, 8'h03, 8'h04};
    #1;
    `checkh(j, 32'h01020304);
    `checkh(u_in.i, 32'h01020304);
    q.push_back(8'h05);
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
