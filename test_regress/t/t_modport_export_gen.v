// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A module connected to a modport exporting a task need define it only
// when elaborated (IEEE 1800-2023 25.7)

interface ifc;
  logic [7:0] data;
  modport provider(output data, export task send(input logic [7:0] val));
  modport user(input data, import task send(input logic [7:0] val));
endinterface

module provider (
    ifc.provider p
);
  task p.send(input logic [7:0] val);
    p.data = val;
  endtask
endmodule

// Does not define 'send', so is legal only where not elaborated
module none (
    ifc.provider p
);
endmodule

module wrapper (
    ifc.provider p
);
  none u_none (.p(p));
endmodule

// Passes the port on to the module defining 'send'
module pass_through (
    ifc.provider p
);
  provider u_provider (.p(p));
endmodule

module pass_star (
    ifc.provider p
);
  provider u_provider (.*);
endmodule

module t #(
    parameter bit USE_NONE = 0,
    parameter int N_NONE = 0
);
  ifc i ();
  provider u_provider (.p(i));
  ifc j ();
  pass_through u_pass (.p(j));
  ifc k ();
  pass_star u_star (.p(k));

  if (USE_NONE) begin : g_if
    none u_none (.p(i));
  end
  for (genvar k = 0; k < N_NONE; ++k) begin : g_for
    none u_none (.p(i));
  end
  case (N_NONE)
    1: begin : g_case
      wrapper u_wrapper (.p(i));
    end
    default: ;
  endcase

  initial begin
    i.send(8'h5a);
    j.send(8'ha5);
    k.send(8'h3c);
    if (i.data !== 8'h5a) $stop;
    if (j.data !== 8'ha5) $stop;
    if (k.data !== 8'h3c) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
