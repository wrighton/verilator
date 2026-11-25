// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub #(
    parameter bit EN = 0
);
  if (EN) begin : g
    function automatic int f();
      return 1;
    endfunction
    task automatic tsk();
    endtask
    function void pre_randomize();
    endfunction
    function int randomize();
      return 1;
    endfunction
    function void srandom(int seed);
    endfunction
  end
endmodule

interface ifc #(
    parameter bit EN = 0
);
  if (EN) begin : g
    function automatic int f();
      return 1;
    endfunction
  end
endinterface

module t;
  sub u ();
  ifc i ();
  initial begin
    // Bad: block 'g' is not generated
    if (u.g.f() != 1) $stop;
    u.g.tsk();
    u.g.pre_randomize();
    void'(u.g.randomize());
    u.g.srandom(1);
    if (i.g.f() != 1) $stop;
  end
endmodule
