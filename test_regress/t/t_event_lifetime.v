// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Automatic events whose storage ends within the time step they are triggered
// in (IEEE 1800-2023 15.5.3)
module t;
`ifdef TEST_ASSIGNABLE
  // The same cases in a design that assigns events
  class EventPair;
    event assigned_from;
    event assigned_to;
    function void merge();
      assigned_to = assigned_from;
    endfunction
  endclass
  initial begin
    EventPair pair;
    pair = new;
    pair.merge();
  end
`endif

  // Test: event in an automatic function
  function automatic int func_triggered();
    // verilator no_inline_task
    event e;
    ->e;
    return e.triggered ? 1 : 0;
  endfunction
  initial begin
    int n;
    n = 0;
    repeat (3) begin
      n += func_triggered();
      #1;
    end
    `checkd(n, 3);
  end

  // Test: event in an automatic task, also after time advances
  task automatic task_untriggered(output int r);
    // verilator no_inline_task
    event e;
    ->e;
    #1;
    r = e.triggered ? 0 : 1;
  endtask
  initial begin
    int r1;
    int r2;
    task_untriggered(r1);
    fork
      task_untriggered(r2);
      #3 `checkd(func_triggered(), 1);
    join
    `checkd(r1, 1);
    `checkd(r2, 1);
  end

  // Test: event in an automatic task or fork block that ends in the time step
  task automatic task_ends_in_step();
    // verilator no_inline_task
    event e;
    ->e;
    #0;
  endtask
  initial begin
    repeat (3) begin
      task_ends_in_step();
      #1;
    end
    fork
      begin
        event e;
        ->e;
      end
    join_none
  end

  initial begin
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
