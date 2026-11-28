// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Continuous streaming assignments of queues, written, as port connections or in a combinational
// process: a warning once the stream does not fit, whose result is not checked, again only when
// its width changes or after it fits, per assignment and instance

module sub_in (
    input bit [31:0] i
);
endmodule

module sub_out (
    output bit [11:0] o
);
  assign o = 12'h5dc;
endmodule

// Its warnings, per instance: 40 bits, 48 bits, 40 bits, fits, then 40 bits again
module sub_cont;
  byte q[$];
  int j;
  int k;
  assign j = {>>{q}};
  always_comb k = {>>{q}};

  initial begin
    q = '{8'h01, 8'h02, 8'h03, 8'h04};
    #1;
    `checkh(j, 32'h01020304);
    `checkh(k, 32'h01020304);
    q.push_back(8'h05);
    #3;
    q.push_back(8'h06);
    #1;
    void'(q.pop_back());
    #1;
    void'(q.pop_back());
    #1;
    `checkh(j, 32'h01020304);
    q.push_back(8'h05);
    #2;
  end
endmodule

module t;
  byte q[$];
  byte oq[$];
  int j;
  bit [15:0] a;
  bit [23:0] b;
  int ticks;
  assign j = {>>{q}};
  sub_in u_in (.i({>>{q}}));
  sub_out u_out (.o({>>{oq}}));
  sub_cont u_cont1 ();
  sub_cont u_cont2 ();
  // Assignments on one line warn each
  assign a = {>>{q}}; assign b = {>>{q}};

  initial begin
    q = '{8'h01, 8'h02, 8'h03, 8'h04};
    #1;
    `checkh(j, 32'h01020304);
    `checkh(u_in.i, 32'h01020304);
    q.push_back(8'h05);
    // Evaluations without a change do not warn again
    repeat (8) begin
      ++ticks;
      #1;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
