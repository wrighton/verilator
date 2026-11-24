// DESCRIPTION: Verilator: selected force RHS dependencies
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef logic [6:0] value_t;
  class Value;
    value_t value;
  endclass

  Value objects[2];
  value_t mem[4];
  int i = 0, j = 1;
  bit observe = 0;
  value_t arg = 7'd6;
  value_t dst, from_mem;
  int samples = 0;
  function automatic value_t mix(value_t x);
    return x + 7'd1;
  endfunction

  function automatic value_t count(value_t x);
    ++samples;
    return x + 7'd1;
  endfunction

  initial begin
    mem[1] = 7'd3;
    #1;
    // An unselected receiver can be null. The selected value stays live even when its
    // handle and the variables in its index expression do not change.
    force dst = observe ? mix(arg) + objects[i^j].value : 7'h45;
    if (dst !== 7'h45) $fatal(1, "Unselected null receiver");
    objects[1] = new;
    objects[1].value = 7'd9;
    observe = 1;
    force from_mem = count(arg) + mem[i^j];
    #1;
    if (dst !== 7'd16 || from_mem !== 7'd10 || samples != 1) $fatal(1, "Initial values");
    objects[1].value = 7'd20;
    mem[2] = 7'd4;
    #1;
    if (dst !== 7'd27) $fatal(1, "Member-only change yielded %0d, expected 27", dst);
    if (samples != 1) $fatal(1, "Unselected element resampled the force");
    mem[1] = 7'd5;
    #1;
    if (from_mem !== 7'd12 || samples != 2)
      $fatal(1, "Selected fixed-array element did not update");
    release from_mem;
    observe = 0;
    i = 7;
    #1;
    if (dst !== 7'h45) $fatal(1, "Unselected out-of-bounds receiver");
    release dst;
    objects[1] = null;
    #1;
    if (dst !== 7'h45 || from_mem !== 7'd12) $fatal(1, "Released variables did not hold");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
