// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// %m in fork branches that read a local, so the branch outlives its scope
module t;
  task automatic task_none(int x);
    fork : f
      #1 begin
        `checks($sformatf("%m"), "t.task_none.f");
        $display("[%0t] %m x=%0d", $time, x);
        begin : inner
          `checks($sformatf("%m"), "t.task_none.f.inner");
        end
      end
    join_none
    #2;
  endtask

  task automatic task_any(int x);
    fork
      begin : b
        #1 `checks($sformatf("%m"), "t.task_any.b");
        $info("x=%0d", x);
      end
    join_any
  endtask

  function automatic void func_none(int x);
    fork
      #2 begin
        `checks($sformatf("%m"), "t.func_none");
        assert (x == 0);
      end
    join_none
  endfunction

  class C;
    task run_any(int x);
      fork : f
        #1 begin
          `checks($sformatf("%m"), "t.C.run_any.f");
          $warning("x=%0d", x);
        end
      join_any
    endtask
    task run_none(int x);
      fork
        #3 begin
          `checks($sformatf("%m"), "t.C.run_none");
          $display("[%0t] %m x=%0d", $time, x);
        end
      join_none
    endtask
  endclass

  initial begin : nest
    automatic int y = 1;
    fork : o
      begin
        #10 `checks($sformatf("%m"), "t.nest.o");
        fork : i
          #1 begin
            `checks($sformatf("%m"), "t.nest.o.i");
            $display("[%0t] %m y=%0d", $time, y);
          end
        join_none
      end
    join_none
  end

  initial begin : main
    automatic int y = 3;
    static C c = new;
    fork
      #1 begin
        `checks($sformatf("%m"), "t.main");
        $display("[%0t] %m y=%0d", $time, y);
      end
    join_none
    fork
      begin : ga
        #2 `checks($sformatf("%m"), "t.main.ga");
        assert (y == 0);
      end
    join_any
    task_none(y);
    task_any(y);
    func_none(y);
    c.run_any(y);
    c.run_none(y);
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
