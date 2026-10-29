// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Element of an interface array inside an interface instance as an interface port actual

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ch_if;
  logic [6:0] d;
endinterface

interface bus_if;
  ch_if arr[3:2] ();
  ch_if grid[2][1:0] ();
endinterface

module drv (
    ch_if g,
    input logic [6:0] v
);
  assign g.d = v;
endmodule

module bus_drv (
    bus_if bp,
    input logic [6:0] v
);
  drv u_arr (
      .g(bp.arr[2]),
      .v(v)
  );
  drv u_grid (
      .g(bp.grid[0][1]),
      .v(v + 7'h1)
  );
endmodule

module t;
  logic clk = 0;
  int cyc = 0;
  logic [6:0] val = 7'h11;

  bus_if b ();
  drv u_arr (
      .g(b.arr[3]),
      .v(val)
  );
  drv u_grid (
      .g(b.grid[1][0]),
      .v(~val)
  );

  bus_if pb ();
  bus_drv u_bus (
      .bp(pb),
      .v(val + 7'h20)
  );

  always #1 clk = ~clk;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    val <= val + 7'h13;
    `checkh(b.arr[3].d, val);
    `checkh(b.grid[1][0].d, ~val);
    `checkh(pb.arr[2].d, val + 7'h20);
    `checkh(pb.grid[0][1].d, val + 7'h21);
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
