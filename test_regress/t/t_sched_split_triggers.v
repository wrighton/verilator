// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Trigger computation is split even where it has a statement for every
// sensitivity (initialization time triggers with --x-initial-edge), or for
// every interface member written through a virtual interface

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifc;
  logic sig = 1'b1;
endinterface

class Driver;
  virtual ifc vif;
  function new(virtual ifc v);
    vif = v;
  endfunction
  task set(logic v);
    vif.sig = v;
  endtask
endclass

module t;
  localparam int N = 16;
  ifc ifcs[N] ();
  Driver drvs[N];
  int cnt[N];
  for (genvar i = 0; i < N; ++i) begin : g_ifc
    initial drvs[i] = new(ifcs[i]);
    always @(posedge ifcs[i].sig) cnt[i] <= cnt[i] + 1;
  end

  initial begin
    #1;
    foreach (cnt[i]) `checkd(cnt[i], 1);
    foreach (drvs[i]) drvs[i].set(1'b0);
    #1;
    foreach (drvs[i]) drvs[i].set(1'b1);
    #1;
    foreach (cnt[i]) `checkd(cnt[i], 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
