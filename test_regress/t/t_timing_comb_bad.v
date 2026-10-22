// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  logic a = 0;
  logic b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14;

  task t_delay();
    #1;
  endtask
  task t_calls_delay();
    t_delay();
  endtask
  task t_no_timing(output logic o);
    o = f_no_timing();
    b12 <= #1 a;
  endtask
  task t_join_none();
    fork
      #1;
    join_none
  endtask
  task t_join();
    fork
      #1;
    join
  endtask
  function automatic logic f_no_timing();
    return a;
  endfunction

  always_comb begin
    #1 b1 = a;  // <--- Bad
  end
  always_comb begin
    @(a);  // <--- Bad
    b2 = a;
  end
  always_comb begin
    wait (a);  // <--- Bad
    b3 = a;
  end
  always_comb begin
    fork  // <--- Bad
      b4 = a;
    join
  end
  always_comb begin
    fork  // <--- Bad
      b5 = a;
    join_any
  end
  always_comb begin
    b6 = #1 a;  // <--- Bad
  end
  always_comb begin
    b14 = @(a) a;  // <--- Bad
  end
  always_comb begin
    t_delay();  // <--- Bad
    t_calls_delay();  // <--- Bad
    t_join();  // <--- Bad
    b7 = a;
  end
  always_latch begin
    #1 b8 = a;  // <--- Bad
  end
  default clocking @(posedge a);
  endclocking
  always_comb begin
    // Cycle delay in a property is legal, but unsupported
    assert property (a ##1 a);
  end

  // Legal
  always_comb begin
    t_no_timing(b9);
    t_join_none();
    b13 = f_no_timing();
    fork
      #1;
      t_delay();
    join_none
    b10 = a;
  end
  always_comb begin
    b11 <= #1 a;
  end

endmodule
