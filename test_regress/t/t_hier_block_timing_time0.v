// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // An export that needs a process, and a context import, which may call it
  export "DPI-C" task tb_disable_fork;
  task tb_disable_fork;
    disable fork;
  endtask
  import "DPI-C" context function int dpii_context();

  // Instances of a hierarchical block whose inputs have their value from time 0
  logic [6:0] drv = 7'h11;
  logic [6:0] o1, o2;
  sub u1 (
      .i(drv),
      .o(o1)
  );
  sub u2 (
      .i(~drv),
      .o(o2)
  );

  // And an instance whose input changes later
  logic [6:0] drv_late = 7'h00;
  logic [6:0] o3;
  sub u3 (
      .i(drv_late),
      .o(o3)
  );

  int unused = 0;
  always @(drv_late) unused = dpii_context();

  initial begin
    #1;
    `checkh(o1, 7'h11);
    `checkh(o2, 7'h6e);
    `checkh(o3, 7'h00);
    drv_late = 7'h25;
    #1;
    `checkh(o3, 7'h25);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module sub (
    input logic [6:0] i  /*verilator forceable*/,
    output logic [6:0] o
);
  /*verilator hier_block*/
  assign o = i;
endmodule
