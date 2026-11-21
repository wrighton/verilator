// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

module t;

  function automatic int f1(ref int r1);
    fork
      begin
        #1 $stop;
        r1 = 0;
      end
    join_none
  endfunction

  task automatic t1(ref int r1);
    fork
      begin
        #1 $stop;
        r1 = 0;
      end
    join_none
  endtask

  function automatic int f2(ref int r2);
    fork
      begin
        r2 = #5 0;
        $stop;
        r2 = 0;
      end
    join_none
  endfunction

  event e;
  function automatic int f3(ref int r3);
    fork
      begin
        @e $stop;
        r3 = 0;
      end
    join_none
  endfunction

  function automatic int f4(ref int r4);
    fork
      begin
        r4 = @e 0;
        $stop;
        r4 = 0;
      end
    join_none
  endfunction

  int i;

  function automatic int f5(ref int r5);
    fork
      begin
        wait (i == 0) $stop;
        r5 = 0;
      end
    join_none
  endfunction

  // Nested fork is killed, but the outer fork may outlive the task
  task automatic t2(ref int r2);
    fork
      begin
        fork
          begin
            #1;
            r2 = 0;
          end
        join_any
        disable fork;
      end
    join_none
  endtask

  // Nested fork is not killed, so may outlive the task
  task automatic t3(ref int r3);
    fork
      begin
        fork
          begin
            #1;
            r3 = 0;
          end
        join_any
      end
    join
  endtask

  function automatic int bump(ref int x);
    x = x + 1;
    return x;
  endfunction

  // Reference passed on from the right-hand side of a nonblocking assignment
  task automatic t4(ref int r4);
    fork
      begin
        #1;
        i <= bump(r4);
      end
    join_none
  endtask

endmodule
