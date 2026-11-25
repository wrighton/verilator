// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface ifc;
  logic [6:0] q = 0;
  logic [14:0] w = 0;
  logic [30:0] resp = 0;

  function automatic logic [6:0] peek();
    // verilator no_inline_task
    return q;
  endfunction
endinterface

// Writes a member by nonblocking assignment through a port
module dut (
    input clk,
    input [30:0] data,
    ifc b
);
  logic [30:0] acc = 0;
  always @(posedge clk) begin
    acc <= acc + data;
    b.resp <= acc ^ data;
  end
endmodule

// Reads the member through a virtual interface
module vmon (
    input clk
);
  virtual ifc v;
  logic [30:0] sum = 0;
  always @(posedge clk) if (v != null) sum <= sum + v.resp;
endmodule

// Reads the member through a port
module pmon (
    input clk,
    ifc b
);
  logic [30:0] sum = 0;
  always @(posedge clk) sum <= sum + b.resp;
endmodule

module t (
    input clk
);
  int cyc = 0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Monitors reading through a virtual interface what a design writes by
  // nonblocking assignment see the same values as reading through a port
  for (genvar g = 0; g < 16; ++g) begin : agent
    ifc b ();
    dut d (
        .clk,
        .data(crc[g*2+:31]),
        .b
    );
    vmon vm (.clk);
    pmon pm (
        .clk,
        .b
    );
    initial vm.v = b;
    always @(posedge clk) if (cyc > 1) `checkh(vm.sum, pm.sum);
  end
endmodule
