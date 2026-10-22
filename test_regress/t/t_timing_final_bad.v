// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  event e;
  logic a = 0;
  logic b;

  task t_delay();
    #1;
  endtask
  task t_calls_delay();
    t_delay();
  endtask
  function automatic logic f_no_timing();
    return a;
  endfunction
  task t_no_timing();
    b = f_no_timing();
    b <= #1 a;
  endtask
  task t_calls_no_timing();
    t_no_timing();
  endtask
  task t_join();
    fork
      #1;
    join
  endtask
  task t_join_none();
    fork
      #1;
    join_none
  endtask

  final begin
    t_delay();  // <--- Bad
    t_calls_delay();  // <--- Bad
    t_join();  // <--- Bad
    @e;  // <--- Bad
    wait (a);  // <--- Bad
    fork  // <--- Bad
      b = a;
    join
    b = @e a;  // <--- Bad
    b <= @e a;  // <--- Bad
  end

  // Legal
  final begin
    t_calls_no_timing();
    t_join_none();
    b = f_no_timing();
    fork
      t_delay();
    join_none
  end

endmodule
