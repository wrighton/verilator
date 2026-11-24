// DESCRIPTION: Verilator: VPI force of a port of a library instance, with timing
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  logic [6:0] drv = 0;
  logic [6:0] o;
  sub u (
      .i(drv),
      .o(o)
  );

  // An export that needs a process
  export "DPI-C" task tb_wait_fork;
  task tb_wait_fork;
    wait fork;
  endtask

  // Forces u.i through the VPI
  import "DPI-C" context function void dpii_force(input int value);

  initial begin
    process p;
    int unsigned rand_first, rand_again;
    #1 drv = 7'h11;
    #1;
    `checkh(o, 7'h11);
    // The force keeps the random number stream of this process
    p = process::self();
    p.srandom(1);
    rand_first = $urandom;
    p.srandom(1);
    dpii_force('h25);
    rand_again = $urandom;
    `checkh(rand_again, rand_first);
    #1;
    `checkh(o, 7'h25);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module sub (
    input logic [6:0] i  /*verilator public_flat_rw*/  /*verilator forceable*/,
    output logic [6:0] o
);
  /*verilator hier_block*/
  assign o = i;
endmodule
