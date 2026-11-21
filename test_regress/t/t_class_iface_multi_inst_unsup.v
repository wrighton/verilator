// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc (
    input int v
);
  import "DPI-C" function int abs(int x);
  function int getv();
    return v;
  endfunction
  function automatic int dbl(int x);
    return 2 * x;
  endfunction
  function int next();
    int cnt;
    cnt++;
    return cnt;
  endfunction
  class C;
    function int get();
      return v;
    endfunction
  endclass
  class Calls;
    function int call();
      return getv();
    endfunction
  endclass
  class Counts;
    function int count();
      return next();
    endfunction
  endclass
  // Supported, as these do not refer to the interface's instance
  class Ok;
    function int dpi();
      return abs(-1);
    endfunction
    function int pure2();
      return dbl(1);
    endfunction
  endclass
  C c = new;
  Calls calls = new;
  Counts counts = new;
  Ok ok = new;
endinterface

module t;
  ifc i1 (.v(1));
  ifc i2 (.v(2));
  initial begin
    $display("%0d %0d %0d %0d %0d %0d", i1.c.get(), i2.c.get(), i1.calls.call(), i1.ok.dpi(),
             i2.ok.pure2(), i1.counts.count());
    $finish;
  end
endmodule
