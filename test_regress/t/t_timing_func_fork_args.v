// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t;
  localparam realtime STEP = 1ns;
  event e;
  int i = 1;
  bit [7:0] completed;

  function automatic int f1(output int o1);
    f1 = 1;
    o1 = 2;
    fork
      begin
        #STEP;
        f1 = 11;
        o1 = 12;
        `checkd(f1, 11);
        `checkd(o1, 12);
        completed[0] = 1;
      end
    join_none
  endfunction

  task automatic t1(output int o1);
    o1 = 3;
    fork
      begin
        #STEP;
        o1 = 13;
        `checkd(o1, 13);
        completed[1] = 1;
      end
    join_none
  endtask

  function automatic int f2(inout int io2);
    f2 = 4;
    fork
      begin
        f2 = #STEP 14;
        `checkd(io2, 5);
        io2 = 15;
        completed[2] = 1;
      end
    join_none
  endfunction

  function automatic int f3(output int o3);
    f3 = 6;
    o3 = 7;
    fork
      begin
        @e;
        f3 = 16;
        o3 = 17;
        completed[3] = 1;
      end
    join_none
  endfunction

  function automatic int f4(inout int io4);
    f4 = 8;
    fork
      begin
        f4 = @e 18;
        `checkd(io4, 9);
        io4 = 19;
        completed[4] = 1;
      end
    join_none
  endfunction

  function automatic int f5(output int o5);
    f5 = 10;
    o5 = 11;
    fork
      begin
        wait (i == 0);
        f5 = 20;
        o5 = 21;
        completed[5] = 1;
      end
    join_none
  endfunction

  // A nested join_any/disable fork does not discard the outer fork's captured formal.
  task automatic t2(output int o2);
    o2 = 12;
    fork
      begin
        fork
          begin
            #STEP;
            o2 = 22;
          end
        join_any
        disable fork;
        `checkd(o2, 22);
        completed[6] = 1;
      end
    join_none
  endtask

  // A waiting parent copies out the child's value when it eventually returns.
  task automatic t3(output int o3);
    fork
      begin
        fork
          begin
            #STEP;
            o3 = 23;
            completed[7] = 1;
          end
        join_any
      end
    join
  endtask

  initial begin
    begin
      int result, arg;
      result = f1(arg);
      #(2 * STEP);
      `checkd(result, 1);
      `checkd(arg, 2);
    end
    begin
      int arg;
      t1(arg);
      #(2 * STEP);
      `checkd(arg, 3);
    end
    begin
      int result, arg;
      arg = 5;
      result = f2(arg);
      #(2 * STEP);
      `checkd(result, 4);
      `checkd(arg, 5);
    end
    begin
      int result, arg;
      result = f3(arg);
      #STEP;
      ->e;
      #STEP;
      `checkd(result, 6);
      `checkd(arg, 7);
    end
    begin
      int result, arg;
      arg = 9;
      result = f4(arg);
      #STEP;
      ->e;
      #STEP;
      `checkd(result, 8);
      `checkd(arg, 9);
    end
    begin
      int result, arg;
      result = f5(arg);
      #STEP;
      i = 0;
      #STEP;
      `checkd(result, 10);
      `checkd(arg, 11);
    end
    begin
      int arg;
      t2(arg);
      #(2 * STEP);
      `checkd(arg, 12);
    end
    begin
      int arg;
      t3(arg);
      `checkd(arg, 23);
    end
    `checkd(completed, 8'hff);
    $info("t_timing_func_fork_args PASSED: *-* All Finished *-*");
  end
endmodule
