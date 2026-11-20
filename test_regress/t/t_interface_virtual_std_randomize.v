// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface gen_if;
  logic [6:0] a;
  int unsigned d;
  task automatic pick();
    if (std::randomize(d) with {d inside {[1:100]};} != 1) `stop;
  endtask
endinterface

class driver;
  virtual gen_if vif;
  task run();
    vif.pick();
    vif.a = 7'(vif.d);
  endtask
endclass

module t;
  gen_if g ();
  // Continuous assignments must follow writes made through the virtual interface
  logic [6:0] y;
  int unsigned yd;
  assign y = g.a;
  assign yd = g.d;

  initial begin
    automatic driver drv = new;
    drv.vif = g;
    repeat (10) begin
      drv.run();
      #1;
      `checkd(y, 7'(g.d));
      `checkd(yd, g.d);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
