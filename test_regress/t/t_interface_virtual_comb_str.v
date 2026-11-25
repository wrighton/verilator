// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface ifc;
  string name;
  int data;

  function automatic int name_len();
    // verilator no_inline_task
    return name.len() + data;
  endfunction
endinterface

module t;
  localparam realtime STEP = 1ns;
  bit clk;
  bit kick;
  int stimulus;
  ifc i ();
  virtual ifc vi;
  always @(posedge clk) i.data <= stimulus;

  // Combinational reads through a virtual interface of a string member, which
  // also depend on another input
  int direct_len;
  always_comb direct_len = vi == null ? 0 : vi.name.len() + int'(kick);
  int method_len;
  always_comb method_len = vi == null ? 0 : vi.name_len() + int'(kick);

  initial begin
    vi = i;
    i.name = "four";
    for (int k = 1; k <= 3; ++k) begin
      stimulus = k * 17;
      #STEP clk = 1;
      #STEP kick = ~kick;
      #STEP;
      `checkd(direct_len, 4 + int'(kick));
      `checkd(method_len, 4 + stimulus + int'(kick));
      clk = 0;
      #STEP;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
