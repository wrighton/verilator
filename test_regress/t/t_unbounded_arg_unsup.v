// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// '$' is only an actual argument of an untyped sequence or property formal (IEEE 1800-2023 16.8)
module t (
  input clk
);
  typedef struct {int a;} st_t;
  logic a, b;
  int x;
  int q[$];

  property p_typed(int r);
    @(posedge clk) a |-> ##[1:r] b;
  endproperty
  property p_struct(st_t r);
    @(posedge clk) a |-> ##[1:r.a] b;
  endproperty
  function automatic int f(int r);
    return r;
  endfunction

  assert property (p_typed($));
  assert property (p_struct($));
  initial x = f($);
  initial q.push_back($);
  initial begin
    randsequence(main)
      main : prod($);
      prod(int r) : { x = r; };
    endsequence
  end
endmodule
