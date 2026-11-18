// DESCRIPTION: Verilator: Assertion control scope that is a task of a base class
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  class B;
    task tk();
      check : assert (1'b1);
    endtask
  endclass
  class D extends B;
    function void off();
      $assertoff(0, tk);
    endfunction
  endclass
  initial begin
    automatic D d = new;
    d.off();
    d.tk();
  end
endmodule
