// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Functions with output, inout or ref arguments called outside procedural
// statements or in event expressions (IEEE 1800-2023 13.4)

module sub (
    input int a
);
endmodule

module t;
  int x, y, z;

  function automatic int fout(output int o);
    o = 1;
    return 2;
  endfunction
  function automatic int finout(inout int o);
    return o;
  endfunction
  function automatic int fref(ref int r);
    return r;
  endfunction
  // Legal in all these contexts
  function automatic int fconstref(const ref int r, input int i);
    return r + i;
  endfunction

  assign x = fout(y);  // BAD
  wire [31:0] w = finout(y);  // BAD
  assign z = fconstref(y, 1);

  sub u (.a(fref(y)));  // BAD

  // verilator lint_off IEEEMAYDEPRECATE
  initial begin
    @(fout(y));  // BAD
    assign x = finout(z);  // BAD
    force z = fref(y);  // BAD
    x = fout(y);
  end
  // verilator lint_on IEEEMAYDEPRECATE

  always @(posedge fref(y)) z = 1;  // BAD

endmodule
