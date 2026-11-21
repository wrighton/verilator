// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc;
  logic [7:0] a;
  logic [7:0] x;
  function automatic logic [7:0] nba_func(logic [7:0] v);
    x <= v;  // <--- Error
    return v;
  endfunction
  wire [7:0] y = nba_func(a);
endinterface

module t;
  logic [7:0] a;
  logic [7:0] x;
  event e;

  function automatic logic [7:0] nba_func(logic [7:0] v);
    x <= v;  // <--- Error
    return v + 8'd1;
  endfunction
  wire [7:0] y = nba_func(a);

  function automatic logic [7:0] nba_event(logic [7:0] v);
    ->>e;  // <--- Error
    return v;
  endfunction
  logic [7:0] z;
  assign z = nba_event(a);

  ifc i ();
endmodule
