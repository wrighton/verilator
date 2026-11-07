// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

class Counter;
  static int n;
  static function int count(int x);
    n++;
    return x;
  endfunction
endclass

// Side effects of a function called in an array method 'with' clause
module t;
  int cnt;
  int q[$] = '{1, 2, 3};

  function automatic int count(int x);
    cnt++;
    return x;
  endfunction

  initial begin
    int r;
    int zero;
    int found[$];

    cnt = 0;
    r = (q.sum with (count(item))) * 0;
    `checkd(cnt, 3);

    cnt = 0;
    zero = 0;
    r = (q.sum with (count(item))) * zero;
    `checkd(cnt, 3);

    cnt = 0;
    r = q.sum with (count(item));
    r = 5;
    `checkd(cnt, 3);

    Counter::n = 0;
    r = (q.sum with (Counter::count(item))) * zero;
    r = q.sum with (Counter::count(item));
    r = 5;
    `checkd(Counter::n, 6);

    cnt = 0;
    r = (q.sum with (count(item))) ^ (q.sum with (count(item)));
    `checkd(r, 0);
    `checkd(cnt, 6);

    cnt = 0;
    void'(q.sum with (count(item)));
    `checkd(cnt, 3);

    cnt = 0;
    if ((q.sum with (count(item))) != 0) begin
    end
    `checkd(cnt, 3);

    cnt = 0;
    found = q.find with (count(item) > 1);
    `checkd(found.size(), 2);
    `checkd(cnt, 3);

    // As an array index, bounds checked as the array size is not a power of 2
    begin
      int arr[5];
      arr[1] = 11;
      cnt = 0;
      `checkd(arr[(q.sum with (count(item))) - 5], 11);
      `checkd(cnt, 3);
      cnt = 0;
      `checkd(arr[q.sum with (count(item))], 0);  // Index 6 is out of range
      `checkd(cnt, 3);
      cnt = 0;
      arr[(q.sum with (count(item))) - 4] = 7;
      `checkd(arr[2], 7);
      `checkd(cnt, 3);
      cnt = 0;
      arr[q.sum with (count(item))] = 8;  // Index 6 is out of range, so nothing is written
      `checkd(cnt, 3);
      `checkd(arr.sum(), 18);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
