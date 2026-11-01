// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Functions and tasks that are not inlined, with bodies larger than
// --output-split-cfuncs. Parts of them are moved into separate functions,
// which must keep their arguments, local variables, return values and jumps
// working.

typedef struct packed {
  logic [63:0] base;
  logic [31:0] size;
  logic [7:0] attr;
} region_t;

class Base;
  int m_base;
  function new(int seed);
    m_base = seed;
  endfunction
endclass

class MemView extends Base;
  region_t m_cfg[string];
  region_t m_arr[int];
  int m_ctor;

  // The super.new call stays in the constructor
  function new(int seed);
    super.new(seed + 1);
    m_ctor = seed;
    m_ctor = m_ctor * 3 + 0;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 1;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 2;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 3;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 4;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 5;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 6;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 7;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 8;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 9;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 10;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 11;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 12;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 13;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 14;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 15;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 16;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 17;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 18;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 19;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 20;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 21;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 22;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 23;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 24;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 25;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 26;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 27;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 28;
    m_ctor ^= m_ctor >>> 2;
    m_ctor = m_ctor * 3 + 29;
    m_ctor ^= m_ctor >>> 2;
  endfunction

  // A memory map: straight-line statements using an argument, a local and members
  task load(input logic [63:0] base, output int nloaded);
    automatic int sz = 16;
    m_cfg["r0"] = '{base: base + 64'h000, size: sz, attr: 8'd0};
    m_arr[0] = '{base: base + 64'h0000, size: sz * 2, attr: 8'd1};
    sz += 1;
    m_cfg["r1"] = '{base: base + 64'h100, size: sz, attr: 8'd1};
    m_arr[1] = '{base: base + 64'h1000, size: sz * 2, attr: 8'd2};
    sz += 2;
    m_cfg["r2"] = '{base: base + 64'h200, size: sz, attr: 8'd2};
    m_arr[2] = '{base: base + 64'h2000, size: sz * 2, attr: 8'd3};
    sz += 3;
    m_cfg["r3"] = '{base: base + 64'h300, size: sz, attr: 8'd3};
    m_arr[3] = '{base: base + 64'h3000, size: sz * 2, attr: 8'd4};
    sz += 1;
    m_cfg["r4"] = '{base: base + 64'h400, size: sz, attr: 8'd4};
    m_arr[4] = '{base: base + 64'h4000, size: sz * 2, attr: 8'd5};
    sz += 2;
    m_cfg["r5"] = '{base: base + 64'h500, size: sz, attr: 8'd5};
    m_arr[5] = '{base: base + 64'h5000, size: sz * 2, attr: 8'd6};
    sz += 3;
    m_cfg["r6"] = '{base: base + 64'h600, size: sz, attr: 8'd6};
    m_arr[6] = '{base: base + 64'h6000, size: sz * 2, attr: 8'd7};
    sz += 1;
    m_cfg["r7"] = '{base: base + 64'h700, size: sz, attr: 8'd7};
    m_arr[7] = '{base: base + 64'h7000, size: sz * 2, attr: 8'd8};
    sz += 2;
    m_cfg["r8"] = '{base: base + 64'h800, size: sz, attr: 8'd8};
    m_arr[8] = '{base: base + 64'h8000, size: sz * 2, attr: 8'd9};
    sz += 3;
    m_cfg["r9"] = '{base: base + 64'h900, size: sz, attr: 8'd9};
    m_arr[9] = '{base: base + 64'h9000, size: sz * 2, attr: 8'd10};
    sz += 1;
    m_cfg["r10"] = '{base: base + 64'ha00, size: sz, attr: 8'd10};
    m_arr[10] = '{base: base + 64'ha000, size: sz * 2, attr: 8'd11};
    sz += 2;
    m_cfg["r11"] = '{base: base + 64'hb00, size: sz, attr: 8'd11};
    m_arr[11] = '{base: base + 64'hb000, size: sz * 2, attr: 8'd12};
    sz += 3;
    m_cfg["r12"] = '{base: base + 64'hc00, size: sz, attr: 8'd12};
    m_arr[12] = '{base: base + 64'hc000, size: sz * 2, attr: 8'd13};
    sz += 1;
    m_cfg["r13"] = '{base: base + 64'hd00, size: sz, attr: 8'd13};
    m_arr[13] = '{base: base + 64'hd000, size: sz * 2, attr: 8'd14};
    sz += 2;
    m_cfg["r14"] = '{base: base + 64'he00, size: sz, attr: 8'd14};
    m_arr[14] = '{base: base + 64'he000, size: sz * 2, attr: 8'd15};
    sz += 3;
    m_cfg["r15"] = '{base: base + 64'hf00, size: sz, attr: 8'd15};
    m_arr[15] = '{base: base + 64'hf000, size: sz * 2, attr: 8'd16};
    sz += 1;
    m_cfg["r16"] = '{base: base + 64'h1000, size: sz, attr: 8'd16};
    m_arr[16] = '{base: base + 64'h10000, size: sz * 2, attr: 8'd17};
    sz += 2;
    m_cfg["r17"] = '{base: base + 64'h1100, size: sz, attr: 8'd17};
    m_arr[17] = '{base: base + 64'h11000, size: sz * 2, attr: 8'd18};
    sz += 3;
    m_cfg["r18"] = '{base: base + 64'h1200, size: sz, attr: 8'd18};
    m_arr[18] = '{base: base + 64'h12000, size: sz * 2, attr: 8'd19};
    sz += 1;
    m_cfg["r19"] = '{base: base + 64'h1300, size: sz, attr: 8'd19};
    m_arr[19] = '{base: base + 64'h13000, size: sz * 2, attr: 8'd20};
    sz += 2;
    m_cfg["r20"] = '{base: base + 64'h1400, size: sz, attr: 8'd20};
    m_arr[20] = '{base: base + 64'h14000, size: sz * 2, attr: 8'd21};
    sz += 3;
    m_cfg["r21"] = '{base: base + 64'h1500, size: sz, attr: 8'd21};
    m_arr[21] = '{base: base + 64'h15000, size: sz * 2, attr: 8'd22};
    sz += 1;
    m_cfg["r22"] = '{base: base + 64'h1600, size: sz, attr: 8'd22};
    m_arr[22] = '{base: base + 64'h16000, size: sz * 2, attr: 8'd23};
    sz += 2;
    m_cfg["r23"] = '{base: base + 64'h1700, size: sz, attr: 8'd23};
    m_arr[23] = '{base: base + 64'h17000, size: sz * 2, attr: 8'd24};
    sz += 3;
    nloaded = m_cfg.size() + m_arr.size();
  endtask

  // The 'break' and the 'return' jump out, so they stay in place
  function int sum(input int limit, ref int count);
    automatic int acc = 0;
    for (int i = 0; i < 24; i++) begin
      if (acc > limit) break;
      acc += m_arr[i].size;
      count++;
    end
    acc += m_cfg["r0"].size;
    count++;
    acc += m_cfg["r1"].size;
    count++;
    acc += m_cfg["r2"].size;
    count++;
    acc += m_cfg["r3"].size;
    count++;
    acc += m_cfg["r4"].size;
    count++;
    acc += m_cfg["r5"].size;
    count++;
    acc += m_cfg["r6"].size;
    count++;
    acc += m_cfg["r7"].size;
    count++;
    acc += m_cfg["r8"].size;
    count++;
    acc += m_cfg["r9"].size;
    count++;
    acc += m_cfg["r10"].size;
    count++;
    acc += m_cfg["r11"].size;
    count++;
    acc += m_cfg["r12"].size;
    count++;
    acc += m_cfg["r13"].size;
    count++;
    acc += m_cfg["r14"].size;
    count++;
    if (acc > limit) return -1;
    acc += int'(m_cfg["r15"].attr);
    count++;
    acc += int'(m_cfg["r16"].attr);
    count++;
    acc += int'(m_cfg["r17"].attr);
    count++;
    acc += int'(m_cfg["r18"].attr);
    count++;
    acc += int'(m_cfg["r19"].attr);
    count++;
    acc += int'(m_cfg["r20"].attr);
    count++;
    acc += int'(m_cfg["r21"].attr);
    count++;
    acc += int'(m_cfg["r22"].attr);
    count++;
    acc += int'(m_cfg["r23"].attr);
    count++;
    acc += int'(m_cfg["r0"].attr);
    count++;
    acc += int'(m_cfg["r1"].attr);
    count++;
    acc += int'(m_cfg["r2"].attr);
    count++;
    acc += int'(m_cfg["r3"].attr);
    count++;
    acc += int'(m_cfg["r4"].attr);
    count++;
    acc += int'(m_cfg["r5"].attr);
    count++;
    return acc;
  endfunction

  // A loop that is not unrolled, with a 'continue'
  function int loopy(int n);
    automatic int acc = 0;
    for (int i = 0; i < n; i++) begin
      if (i == 2) continue;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
      acc = acc * 3 + i;
      acc ^= acc >>> 2;
    end
    return acc;
  endfunction

  static function int smix(int x);
    automatic int y = x;
    y = y * 3 + 0;
    y ^= y >>> 2;
    y = y * 3 + 1;
    y ^= y >>> 2;
    y = y * 3 + 2;
    y ^= y >>> 2;
    y = y * 3 + 3;
    y ^= y >>> 2;
    y = y * 3 + 4;
    y ^= y >>> 2;
    y = y * 3 + 5;
    y ^= y >>> 2;
    y = y * 3 + 6;
    y ^= y >>> 2;
    y = y * 3 + 7;
    y ^= y >>> 2;
    y = y * 3 + 8;
    y ^= y >>> 2;
    y = y * 3 + 9;
    y ^= y >>> 2;
    y = y * 3 + 10;
    y ^= y >>> 2;
    y = y * 3 + 11;
    y ^= y >>> 2;
    y = y * 3 + 12;
    y ^= y >>> 2;
    y = y * 3 + 13;
    y ^= y >>> 2;
    y = y * 3 + 14;
    y ^= y >>> 2;
    y = y * 3 + 15;
    y ^= y >>> 2;
    y = y * 3 + 16;
    y ^= y >>> 2;
    y = y * 3 + 17;
    y ^= y >>> 2;
    y = y * 3 + 18;
    y ^= y >>> 2;
    y = y * 3 + 19;
    y ^= y >>> 2;
    y = y * 3 + 20;
    y ^= y >>> 2;
    y = y * 3 + 21;
    y ^= y >>> 2;
    y = y * 3 + 22;
    y ^= y >>> 2;
    y = y * 3 + 23;
    y ^= y >>> 2;
    y = y * 3 + 24;
    y ^= y >>> 2;
    y = y * 3 + 25;
    y ^= y >>> 2;
    y = y * 3 + 26;
    y ^= y >>> 2;
    y = y * 3 + 27;
    y ^= y >>> 2;
    y = y * 3 + 28;
    y ^= y >>> 2;
    y = y * 3 + 29;
    y ^= y >>> 2;
    return y;
  endfunction
endclass

// A coroutine, whose statements at the top level move, but not the one keeping
// 'this' alive after the last handle to the object is gone
class Timed;
  static Timed s_handle;
  static int s_result;
  int m;
  task run(int x);
    m = x;
    #1;
    s_handle = null;
    m = m * 3 + 0;
    m ^= m >>> 2;
    m = m * 3 + 1;
    m ^= m >>> 2;
    m = m * 3 + 2;
    m ^= m >>> 2;
    m = m * 3 + 3;
    m ^= m >>> 2;
    m = m * 3 + 4;
    m ^= m >>> 2;
    m = m * 3 + 5;
    m ^= m >>> 2;
    m = m * 3 + 6;
    m ^= m >>> 2;
    m = m * 3 + 7;
    m ^= m >>> 2;
    m = m * 3 + 8;
    m ^= m >>> 2;
    m = m * 3 + 9;
    m ^= m >>> 2;
    #1;
    m = m * 3 + 10;
    m ^= m >>> 2;
    m = m * 3 + 11;
    m ^= m >>> 2;
    m = m * 3 + 12;
    m ^= m >>> 2;
    m = m * 3 + 13;
    m ^= m >>> 2;
    m = m * 3 + 14;
    m ^= m >>> 2;
    m = m * 3 + 15;
    m ^= m >>> 2;
    m = m * 3 + 16;
    m ^= m >>> 2;
    m = m * 3 + 17;
    m ^= m >>> 2;
    m = m * 3 + 18;
    m ^= m >>> 2;
    m = m * 3 + 19;
    m ^= m >>> 2;
    #1;
    m = m * 3 + 20;
    m ^= m >>> 2;
    m = m * 3 + 21;
    m ^= m >>> 2;
    m = m * 3 + 22;
    m ^= m >>> 2;
    m = m * 3 + 23;
    m ^= m >>> 2;
    m = m * 3 + 24;
    m ^= m >>> 2;
    m = m * 3 + 25;
    m ^= m >>> 2;
    m = m * 3 + 26;
    m ^= m >>> 2;
    m = m * 3 + 27;
    m ^= m >>> 2;
    m = m * 3 + 28;
    m ^= m >>> 2;
    m = m * 3 + 29;
    m ^= m >>> 2;
    #1;
    s_result = m;
  endtask
endclass

module t;
  // Same computation as the straight-line bodies, as a loop
  function automatic int mix(int x);
    for (int k = 0; k < 30; k++) begin
      x = x * 3 + k;
      x ^= x >>> 2;
    end
    return x;
  endfunction

  function automatic int mfunc(int x);
    /* verilator no_inline_task */
    x = x * 3 + 0;
    x ^= x >>> 2;
    x = x * 3 + 1;
    x ^= x >>> 2;
    x = x * 3 + 2;
    x ^= x >>> 2;
    x = x * 3 + 3;
    x ^= x >>> 2;
    x = x * 3 + 4;
    x ^= x >>> 2;
    x = x * 3 + 5;
    x ^= x >>> 2;
    x = x * 3 + 6;
    x ^= x >>> 2;
    x = x * 3 + 7;
    x ^= x >>> 2;
    x = x * 3 + 8;
    x ^= x >>> 2;
    x = x * 3 + 9;
    x ^= x >>> 2;
    x = x * 3 + 10;
    x ^= x >>> 2;
    x = x * 3 + 11;
    x ^= x >>> 2;
    x = x * 3 + 12;
    x ^= x >>> 2;
    x = x * 3 + 13;
    x ^= x >>> 2;
    x = x * 3 + 14;
    x ^= x >>> 2;
    x = x * 3 + 15;
    x ^= x >>> 2;
    x = x * 3 + 16;
    x ^= x >>> 2;
    x = x * 3 + 17;
    x ^= x >>> 2;
    x = x * 3 + 18;
    x ^= x >>> 2;
    x = x * 3 + 19;
    x ^= x >>> 2;
    x = x * 3 + 20;
    x ^= x >>> 2;
    x = x * 3 + 21;
    x ^= x >>> 2;
    x = x * 3 + 22;
    x ^= x >>> 2;
    x = x * 3 + 23;
    x ^= x >>> 2;
    x = x * 3 + 24;
    x ^= x >>> 2;
    x = x * 3 + 25;
    x ^= x >>> 2;
    x = x * 3 + 26;
    x ^= x >>> 2;
    x = x * 3 + 27;
    x ^= x >>> 2;
    x = x * 3 + 28;
    x ^= x >>> 2;
    x = x * 3 + 29;
    x ^= x >>> 2;
    return x;
  endfunction

  // User C++ text stays in place, as later text uses the C++ local it declares
  function automatic int cuser(int x);
    /* verilator no_inline_task */
    $c("int tmp = ", x, ";");
    x = x * 3 + 0;
    x ^= x >>> 2;
    x = x * 3 + 1;
    x ^= x >>> 2;
    x = x * 3 + 2;
    x ^= x >>> 2;
    x = x * 3 + 3;
    x ^= x >>> 2;
    x = x * 3 + 4;
    x ^= x >>> 2;
    x = x * 3 + 5;
    x ^= x >>> 2;
    x = x * 3 + 6;
    x ^= x >>> 2;
    x = x * 3 + 7;
    x ^= x >>> 2;
    x = x * 3 + 8;
    x ^= x >>> 2;
    x = x * 3 + 9;
    x ^= x >>> 2;
    x = x * 3 + 10;
    x ^= x >>> 2;
    x = x * 3 + 11;
    x ^= x >>> 2;
    x = x * 3 + 12;
    x ^= x >>> 2;
    x = x * 3 + 13;
    x ^= x >>> 2;
    x = x * 3 + 14;
    x ^= x >>> 2;
    x = x * 3 + 15;
    x ^= x >>> 2;
    x = x * 3 + 16;
    x ^= x >>> 2;
    x = x * 3 + 17;
    x ^= x >>> 2;
    x = x * 3 + 18;
    x ^= x >>> 2;
    x = x * 3 + 19;
    x ^= x >>> 2;
    x = x * 3 + 20;
    x ^= x >>> 2;
    x = x * 3 + 21;
    x ^= x >>> 2;
    x = x * 3 + 22;
    x ^= x >>> 2;
    x = x * 3 + 23;
    x ^= x >>> 2;
    x = x * 3 + 24;
    x ^= x >>> 2;
    x = x * 3 + 25;
    x ^= x >>> 2;
    x = x * 3 + 26;
    x ^= x >>> 2;
    x = x * 3 + 27;
    x ^= x >>> 2;
    x = x * 3 + 28;
    x ^= x >>> 2;
    x = x * 3 + 29;
    x ^= x >>> 2;
    return x + $c32("tmp");
  endfunction

  // A DPI export using a module variable, which needs vlSymsp, and calling a function
  // that needs a process, which its new functions take from it
  std::process dexp_proc;
  int dexp_calls = 0;
  export "DPI-C" function dexp;
  function int dexp(int x);
    dexp_calls++;
    dexp_proc = std::process::self();
    x = x * 3 + 0;
    x ^= x >>> 2;
    x = x * 3 + 1;
    x ^= x >>> 2;
    x = x * 3 + 2;
    x ^= x >>> 2;
    x = x * 3 + 3;
    x ^= x >>> 2;
    x = x * 3 + 4;
    x ^= x >>> 2;
    x = x * 3 + 5;
    x ^= x >>> 2;
    x = x * 3 + 6;
    x ^= x >>> 2;
    x = x * 3 + 7;
    x ^= x >>> 2;
    x = x * 3 + 8;
    x ^= x >>> 2;
    x = x * 3 + 9;
    x ^= x >>> 2;
    x = x * 3 + 10;
    x ^= x >>> 2;
    x = x * 3 + 11;
    x ^= x >>> 2;
    x = x * 3 + 12;
    x ^= x >>> 2;
    x = x * 3 + 13;
    x ^= x >>> 2;
    x = x * 3 + 14;
    x ^= x >>> 2;
    x = x * 3 + 15;
    x ^= x >>> 2;
    x = x * 3 + 16;
    x ^= x >>> 2;
    x = x * 3 + 17;
    x ^= x >>> 2;
    x = x * 3 + 18;
    x ^= x >>> 2;
    x = x * 3 + 19;
    x ^= x >>> 2;
    x = x * 3 + 20;
    x ^= x >>> 2;
    x = x * 3 + 21;
    x ^= x >>> 2;
    x = x * 3 + 22;
    x ^= x >>> 2;
    x = x * 3 + 23;
    x ^= x >>> 2;
    x = x * 3 + 24;
    x ^= x >>> 2;
    x = x * 3 + 25;
    x ^= x >>> 2;
    x = x * 3 + 26;
    x ^= x >>> 2;
    x = x * 3 + 27;
    x ^= x >>> 2;
    x = x * 3 + 28;
    x ^= x >>> 2;
    x = x * 3 + 29;
    x ^= x >>> 2;
    dexp_calls++;
    dexp_proc = std::process::self();
    return x;
  endfunction

  // Public, so not split: its 'byte' argument is a 'uint32_t' in C++
  // verilator lint_off UNOPTPUBLIC
  function int pubf(int x, byte k);
    /* verilator public */
    // verilator lint_on UNOPTPUBLIC
    x += int'(k);
    x = x * 3 + 0;
    x ^= x >>> 2;
    x = x * 3 + 1;
    x ^= x >>> 2;
    x = x * 3 + 2;
    x ^= x >>> 2;
    x = x * 3 + 3;
    x ^= x >>> 2;
    x = x * 3 + 4;
    x ^= x >>> 2;
    x = x * 3 + 5;
    x ^= x >>> 2;
    x = x * 3 + 6;
    x ^= x >>> 2;
    x = x * 3 + 7;
    x ^= x >>> 2;
    x = x * 3 + 8;
    x ^= x >>> 2;
    x = x * 3 + 9;
    x ^= x >>> 2;
    x = x * 3 + 10;
    x ^= x >>> 2;
    x = x * 3 + 11;
    x ^= x >>> 2;
    x = x * 3 + 12;
    x ^= x >>> 2;
    x = x * 3 + 13;
    x ^= x >>> 2;
    x = x * 3 + 14;
    x ^= x >>> 2;
    x = x * 3 + 15;
    x ^= x >>> 2;
    x = x * 3 + 16;
    x ^= x >>> 2;
    x = x * 3 + 17;
    x ^= x >>> 2;
    x = x * 3 + 18;
    x ^= x >>> 2;
    x = x * 3 + 19;
    x ^= x >>> 2;
    x = x * 3 + 20;
    x ^= x >>> 2;
    x = x * 3 + 21;
    x ^= x >>> 2;
    x = x * 3 + 22;
    x ^= x >>> 2;
    x = x * 3 + 23;
    x ^= x >>> 2;
    x = x * 3 + 24;
    x ^= x >>> 2;
    x = x * 3 + 25;
    x ^= x >>> 2;
    x = x * 3 + 26;
    x ^= x >>> 2;
    x = x * 3 + 27;
    x ^= x >>> 2;
    x = x * 3 + 28;
    x ^= x >>> 2;
    x = x * 3 + 29;
    x ^= x >>> 2;
    return x;
  endfunction

  int seed;
  MemView v;

  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 5;
    v = new(seed);
    `checkd(v.m_base, seed + 1);
    `checkd(v.m_ctor, mix(seed));
    begin : memory_map
      int n;
      int expsz;
      v.load(64'h1000_0000 + 64'(seed), n);
      `checkd(n, 48);
      expsz = 16;
      for (int i = 0; i < 24; i++) begin
        `checkd(v.m_cfg[$sformatf("r%0d", i)].base, 64'h1000_0000 + 64'(seed) + 64'(i * 'h100));
        `checkd(v.m_cfg[$sformatf("r%0d", i)].size, expsz);
        `checkd(v.m_arr[i].size, expsz * 2);
        `checkd(int'(v.m_arr[i].attr), i + 1);
        expsz += i % 3 + 1;
      end
    end
    begin : returns_early
      automatic int count = 0;
      `checkd(v.sum(100, count), -1);
      `checkd(count, 18);
    end
    begin : returns_at_end
      automatic int count = 0;
      automatic int expsum = 0;
      for (int i = 0; i < 24; i++) expsum += v.m_arr[i].size;
      for (int i = 0; i < 15; i++) expsum += v.m_cfg[$sformatf("r%0d", i)].size;
      for (int i = 15; i < 30; i++) expsum += int'(v.m_cfg[$sformatf("r%0d", i % 24)].attr);
      `checkd(v.sum(100000, count), expsum);
      `checkd(count, 54);
    end
    begin : loop_continue
      automatic int expsum = 0;
      for (int i = 0; i < seed; i++) begin
        if (i == 2) continue;
        for (int k = 0; k < 15; k++) begin
          expsum = expsum * 3 + i;
          expsum ^= expsum >>> 2;
        end
      end
      `checkd(v.loopy(seed), expsum);
    end
    `checkd(MemView::smix(seed), mix(seed));
    `checkd(mfunc(seed + 1), mix(seed + 1));
    `checkd(cuser(seed + 5), mix(seed + 5) + seed + 5);
    `checkd(dexp(seed + 2), mix(seed + 2));
    `checkd(dexp_calls, 2);
    `checkd(pubf(seed + 2, 1), mix(seed + 3));
    begin : coroutine
      Timed::s_handle = new;
      Timed::s_handle.run(seed + 4);
      `checkd(Timed::s_handle, null);
      `checkd(Timed::s_result, mix(seed + 4));
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
