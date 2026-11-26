// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A sampled value is the value from before the time slot, also after a constant is assigned in
// the time slot, but that of an automatic variable is its current value (IEEE 1800-2023 16.5.1)
module t;
  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  bit a = 0;
  int data = 37;
  bit sa;
  int sdata;
  int sauto;
  int sloop;
  int sfunc;
  function automatic int f(int x);
    int la;
    la = 3;
    return $sampled(la) + $sampled(x);
  endfunction
  always @(posedge clk) begin
    automatic int la;
    cyc <= cyc + 1;
    a = 1'b1;
    data = 52;
    data = 19;
    la = 3;
    sa = $sampled(a);
    sdata = $sampled(data);
    sauto = $sampled(la);
    for (int i = 4; i < 5; i++) sloop = $sampled(i);
    sfunc = f(10);
    `checkd(sa, cyc != 0);
    `checkd(sdata, cyc == 0 ? 37 : 19);
    `checkd(sauto, 3);
    `checkd(sloop, 4);
    `checkd(sfunc, 13);
  end
  initial begin
    #50;
    `checkd(cyc, 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
