// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 13.4.3: Constant functions shall not themselves use constant functions in
// any context requiring a constant expression

module t;
  function automatic int g(int a);
    return a * 2;
  endfunction

  function automatic int packed_dim(int a);
    logic [g(2)-1:0] v;  // <--- Bad when packed_dim is a constant function
    v = '1;
    return $bits(v) + a;
  endfunction
  localparam int P1 = packed_dim(1);

  function automatic int unpacked_dim();
    begin : blk
      static int arr[g(1)];  // <--- Bad when unpacked_dim is a constant function
      return $size(arr);
    end
  endfunction
  localparam int P2 = unpacked_dim();

  // Ok, as a call in an expression does not require a constant expression
  function automatic int call_in_expr(int a);
    return g(a) + 1;
  endfunction
  localparam int P3 = call_in_expr(3);

  // Ok, as not called as a constant function
  int runtime;
  initial runtime = packed_dim(4);
endmodule
