// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

typedef int arr_t[3];

class Cls;
  int cnt;
  int init_depth;
  function arr_t get_arr(int depth);
    arr_t arr = (depth > 1) ? get_arr(depth - 1) : '{init_depth, init_depth * 2, init_depth * 3};
    cnt++;
    return arr;
  endfunction
endclass

module t;
  Cls c = new;
  initial begin
    arr_t arr;
    c.init_depth = 5;
    arr = (c.init_depth > 0) ? c.get_arr(5) : '{1, 2, 3};

    if (arr[0] != 5) $stop;
    if (arr[1] != 10) $stop;
    if (arr[2] != 15) $stop;

    if (c.cnt != 5) $stop;

    begin
      // An impure source copied element by element is evaluated once
      arr_t q[$];
      int s[5];
      int d[3:0];
      q = '{'{1, 2, 3}, '{4, 5, 6}, '{7, 8, 9}, '{10, 11, 12}, '{13, 14, 15}};
      s[1:3] = q.pop_front();
      if (s[1] != 1 || s[2] != 2 || s[3] != 3) $stop;
      if (q.size() != 4) $stop;
      arr = q.pop_front();
      if (arr[0] != 4 || arr[1] != 5 || arr[2] != 6) $stop;
      if (q.size() != 3) $stop;
      d[2:0] = q.pop_front();
      if (d[2] != 7 || d[1] != 8 || d[0] != 9) $stop;
      if (q.size() != 2) $stop;
      if (q.pop_front() != '{10, 11, 12}) $stop;
      if (q.size() != 1) $stop;
      if (!('{13, 14, 15} == q.pop_front())) $stop;
      if (q.size() != 0) $stop;
      q = '{'{1, 2, 3}, '{4, 5, 6}};
      s[1:3] = (q.size() > 1) ? q.pop_front() : s[0:2];
      if (s[1] != 1 || s[2] != 2 || s[3] != 3) $stop;
      if (q.size() != 1) $stop;
      q = '{'{1, 2, 3}, '{4, 5, 6}};
      d[2:0] = (q.size() > 1) ? q.pop_front() : arr;
      if (d[2] != 1 || d[1] != 2 || d[0] != 3) $stop;
      if (q.size() != 1) $stop;
      q = '{'{1, 2, 3}, '{1, 2, 3}, '{4, 5, 6}};
      if (q.pop_front() != q.pop_front()) $stop;
      if (q.size() != 1) $stop;
    end

    begin
      typedef int arr2_t[2][3];
      arr2_t q[$];
      int s[2][3];
      int t[4];
      q = '{'{'{1, 2, 3}, '{4, 5, 6}}, '{'{7, 8, 9}, '{10, 11, 12}}};
      s = q.pop_front();
      if (s[0][0] != 1 || s[0][2] != 3 || s[1][0] != 4 || s[1][2] != 6) $stop;
      if (q.size() != 1) $stop;
      t = '{1, 2, 3, 4};
      s = (q.size() > 1) ? q.pop_front() : '{t[0:2], t[1:3]};
      if (s[0][0] != 1 || s[0][2] != 3 || s[1][0] != 2 || s[1][2] != 4) $stop;
      if (q.size() != 1) $stop;
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
