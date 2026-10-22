// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc;
  logic [7:0] data;
  modport provider(output data, export task send(input logic [7:0] val),
                   export function int get());
endinterface

// Bad: defines neither exported method
module none (
    ifc.provider p
);
endmodule

// Bad: defines 'send' but not 'get'
module partial (
    ifc.provider p
);
  task p.send(input logic [7:0] val);
    p.data = val;
  endtask
endmodule

module t;
  ifc i1 ();
  ifc i2 ();
  none u_none (.p(i1));
  partial u_partial (.p(i2));
endmodule
