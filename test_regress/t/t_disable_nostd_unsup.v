// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  task tsk;
    fork : frk
      begin
        disable frk;
      end
    join_none
  endtask
endclass

module t;
  task automatic tsk;
    #1;
  endtask

  initial begin
    fork : frk
      #1;
    join_none
    disable frk;
    disable tsk;
    begin : blk_fork
      fork
        #1;
      join_none
      disable blk_fork;
    end
    // Disable of an enclosing block without forks is supported
    begin : blk_jump
      disable blk_jump;
    end
  end
endmodule
