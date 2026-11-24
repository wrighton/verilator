// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc #(
    parameter int W = 8
);
  logic [W-1:0] d;
  modport mp(input d);
endinterface

module child (
    ifc port
);
  int y;
  assign y = $bits(port.d);
endmodule

module leaf (
    ifc port,
    ifc.mp mport
);
  int x;
  assign x = $bits(port.d);
  int z;
  assign z = $bits(mport.d);
  child c (.port(port));
endmodule

module t;
  ifc #(.W(16)) b ();
  // Bad: interface ports not connected, and 'ifc' only used specialized
  leaf c ();
endmodule
