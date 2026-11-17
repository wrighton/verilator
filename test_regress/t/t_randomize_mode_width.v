// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class ModeWidth;
  rand bit x;
  constraint c {x == 0;}

  function bit [1:0] wide_mode;
    return 2'b10;
  endfunction

  task check(input bit [1:0] flag);
    rand_mode(flag);
    rand_mode(wide_mode());
    constraint_mode(flag);
  endtask
endclass

module t;
  initial begin
    automatic ModeWidth obj = new;
    obj.check(2'b10);
  end
endmodule
