// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface inner;
  logic [7:0] q;
endinterface

interface ifc;
  inner n ();
  logic [7:0] q;
  function automatic logic [7:0] fa();
    return q;
  endfunction
  function automatic logic [7:0] fb();
    return q + 8'd1;
  endfunction
endinterface

module sub (
    ifc p,
    output logic [7:0] o1,
    output logic [7:0] o2,
    output logic [7:0] o3
);
  // Suggestions and known scopes list every name of the interface, whether looked up yet or not
  assign o1 = p.fb();
  assign o2 = p.fx();  // BAD: suggests 'fa', the first by name
  assign o3 = p.nosuch.q;  // BAD: lists 'n'
endmodule

module t (
    output logic [7:0] o1,
    output logic [7:0] o2,
    output logic [7:0] o3
);
  ifc i ();
  sub s (
      .p(i),
      .o1,
      .o2,
      .o3
  );
endmodule
