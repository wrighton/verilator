// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

class Cls;
  int x = 100;
  task get_x(output int arg);
    arg = x;
  endtask
endclass

task automatic test;
  int o;
  Cls c = new;
  fork
    c.get_x(o);
  join_any
  `checkd(o, 100);
endtask

class Accessor;
  localparam realtime STEP = 1ns;

  task read_value(input int value, output int result);
    #STEP;
    result = value;
  endtask

  // The caller waits for the child, so the value written after the delay is copied out
  task access(inout int data);
    bit done = 0;
    fork
      begin
        #STEP;
        read_value(data + 7, data);
        done = 1;
      end
    join_none
    wait (done);
  endtask
endclass

module t;
  localparam realtime STEP = 1ns;
  event e;
  int i = 1;
  bit [9:0] completed;

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
        `checkd(f3, 16);
        `checkd(o3, 17);
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
        `checkd(f5, 20);
        `checkd(o5, 21);
        completed[5] = 1;
      end
    join_none
  endfunction

  // A write after a nested join_any/disable fork is seen by the outer fork but not by the caller
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

  // An explicit return still passes the values at return
  function automatic int f6(output int o6);
    o6 = 1;
    fork
      begin
        #STEP;
        f6 = 26;
        o6 = 27;
        `checkd(o6, 27);
        completed[9] = 1;
      end
    join_none
    return 6;
  endfunction

  // join_any returns with the fast branch; the slow branch writes the retained formal later
  task automatic t4(output int o4);
    o4 = 40;
    fork
      #STEP;
      begin
        #(2 * STEP);
        o4 = 41;
      end
    join_any
    fork
      begin
        #(3 * STEP);
        `checkd(o4, 41);
        completed[8] = 1;
      end
    join_none
  endtask

  // Each activation keeps its own formal, also when its caller has already returned
  int overlap_done = 0;
  task automatic t_overlap(input int k, output int o);
    o = k;
    fork
      begin
        #STEP;
        o = k + 100;
        `checkd(o, k + 100);
        ++overlap_done;
      end
    join_none
  endtask
  task automatic short_caller(input int k, output int r);
    int local_v;
    t_overlap(k, local_v);
    r = local_v;
  endtask

  // Other types: the caller gets the values at return, the fork keeps writing its own copies
  typedef int arr3_t[3:1];
  int types_done = 0;
  task automatic t_types(output logic [64:0] o_wide, inout arr3_t io_arr, output string o_str,
                         inout int io_q[$]);
    o_wide = 65'h1_0000_0000_0000_0005;
    io_arr[2] = io_arr[2] + 1;
    o_str = "ret";
    io_q.push_back(7);
    fork
      begin
        #STEP;
        o_wide = ~o_wide;
        io_arr[2] = -1;
        o_str = "late";
        io_q.push_back(8);
        #STEP;
        `checkh(o_wide, 65'h0_ffff_ffff_ffff_fffa);
        `checkd(io_arr[2], -1);
        `checks(o_str, "late");
        `checkd(io_q.size(), 3);
        ++types_done;
      end
    join_none
  endtask

  initial begin
    Accessor accessor;
    int data;
    accessor = new;
    data = -1;
    for (int calls = 1; calls <= 4; ++calls) begin
      accessor.access(data);
      `checkd(data, -1 + 7 * calls);
    end
    test();
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
    begin
      int result, arg;
      result = f6(arg);
      `checkd(result, 6);
      `checkd(arg, 1);
      #(2 * STEP);
      `checkd(result, 6);
      `checkd(arg, 1);
    end
    begin
      int arg;
      t4(arg);
      `checkd(arg, 40);
      #(3 * STEP);
      `checkd(arg, 40);
    end
    begin
      int got[3];
      int r;
      for (int k = 0; k < 3; ++k) t_overlap(k * 7 + 1, got[k]);
      foreach (got[k]) `checkd(got[k], k * 7 + 1);
      short_caller(33, r);
      `checkd(r, 33);
      got[0] = -1;
      #(2 * STEP);
      `checkd(got[0], -1);
      `checkd(got[2], 15);
      `checkd(r, 33);
      `checkd(overlap_done, 4);
    end
    begin
      logic [64:0] wide;
      arr3_t arr;
      string str;
      int q[$];
      arr = '{30, 20, 10};
      q = '{6};
      t_types(wide, arr, str, q);
      `checkh(wide, 65'h1_0000_0000_0000_0005);
      `checkd(arr[2], 21);
      `checks(str, "ret");
      `checkd(q.size(), 2);
      #(3 * STEP);
      `checkh(wide, 65'h1_0000_0000_0000_0005);
      `checkd(arr[2], 21);
      `checkd(arr[3], 30);
      `checks(str, "ret");
      `checkd(q.size(), 2);
      `checkd(q[1], 7);
      `checkd(types_done, 1);
    end
    `checkd(completed, 10'h3ff);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
