// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// A force reading an argument of a static task, called through a virtual interface, keeps
// evaluating that argument, which lives as long as the task it belongs to

module dut (
    input logic [7:0] a,
    output logic [7:0] y
);
  assign y = a;
endmodule

interface force_arg_if;
  logic [7:0] sig;
  task force_a(logic [7:0] v);
    force dut.a = v;
  endtask
  task release_a();
    release dut.a;
  endtask
endinterface

class Driver;
  virtual force_arg_if vif;
  logic [7:0] prop = 8'h44;
  task run();
    vif.force_a(8'h11);
    #1 `checkh(t.y, 8'h11);
    vif.force_a(prop);  // a class property lasts as long as its object
    #1 `checkh(t.y, 8'h44);
    vif.release_a();
    #1 `checkh(t.y, 8'h00);
  endtask
endclass

module t;
  logic [7:0] y;
  dut dut (
      .a(8'h00),
      .y(y)
  );
  bind dut force_arg_if g ();

  initial begin
    automatic Driver d = new;
    d.vif = dut.g;
    d.run();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
