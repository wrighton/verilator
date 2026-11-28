// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

module t;
  typedef bit signed [4:0] s5_t;
  typedef bit signed [69:0] s70_t;
  typedef enum int {
    EN = -2,
    EZ = 0,
    EP = 1
  } e_t;

  initial begin
    begin
      // Test: ordering methods of a queue order signed elements by value
      int q[$];
      int qv[$];
      q = '{5, -7, 3, -1};
      q.sort;
      `checkp(q, "'{'hfffffff9, 'hffffffff, 'h3, 'h5}");
      q.rsort;
      `checkp(q, "'{'h5, 'h3, 'hffffffff, 'hfffffff9}");
      qv = q.min;
      `checkp(qv, "'{'hfffffff9}");
      qv = q.max;
      `checkp(qv, "'{'h5}");
      // Test: a signed 'with' key orders by value
      q.sort with (item);
      `checkp(q, "'{'hfffffff9, 'hffffffff, 'h3, 'h5}");
      q.rsort(x) with (x);
      `checkp(q, "'{'h5, 'h3, 'hffffffff, 'hfffffff9}");
      q.sort with (-item);
      `checkp(q, "'{'h5, 'h3, 'hffffffff, 'hfffffff9}");
      qv = q.min with (item + 1);
      `checkp(qv, "'{'hfffffff9}");
      qv = q.max with (-item);
      `checkp(qv, "'{'hfffffff9}");
      // Test: a real 'with' key orders by value
      q.sort with (real'(item) / 2);
      `checkp(q, "'{'hfffffff9, 'hffffffff, 'h3, 'h5}");
      // Test: an unsigned 'with' key of signed elements orders unsigned
      q.sort with (unsigned'(item));
      `checkp(q, "'{'h3, 'h5, 'hfffffff9, 'hffffffff}");
    end
    begin
      // Test: dynamic and fixed-size arrays, narrow and wide elements
      byte d[];
      byte dv[$];
      s5_t u[4];
      s5_t uv[$];
      longint l[3];
      longint lv[$];
      s70_t w[$];
      s70_t wv[$];
      e_t e[$];
      d = '{8'sd100, -8'sd100, 8'sd0};
      d.sort;
      `checkp(d, "'{'h9c, 'h0, 'h64}");
      dv = d.max;
      `checkp(dv, "'{'h64}");
      u = '{5'sd3, -5'sd16, 5'sd15, -5'sd1};
      u.sort;
      `checkp(u, "'{'h10, 'h1f, 'h3, 'hf}");
      u.rsort;
      `checkp(u, "'{'hf, 'h3, 'h1f, 'h10}");
      uv = u.min;
      `checkp(uv, "'{'h10}");
      l = '{64'sd1 <<< 40, -64'sd1 <<< 40, 64'sd7};
      lv = l.min;
      `checkp(lv, "'{'hffffff0000000000}");
      lv = l.max with (item);
      `checkp(lv, "'{'h10000000000}");
      w = '{70'sd5, -70'sd5, 70'sd1 <<< 68};
      w.sort;
      `checkp(w, "'{'h3ffffffffffffffffb, 'h5, 'h100000000000000000}");
      wv = w.min;
      `checkp(wv, "'{'h3ffffffffffffffffb}");
      e = '{EP, EN, EZ};
      e.sort;
      `checkp(e, "'{'hfffffffe, 'h0, 'h1}");
    end
    begin
      // Test: associative arrays order signed values by value
      int a[string];
      int av[$];
      int wc[*];
      int wcv[$];
      a = '{"x": 4, "y": -4, "z": 0};
      av = a.min;
      `checkp(av, "'{'hfffffffc}");
      av = a.max;
      `checkp(av, "'{'h4}");
      av = a.min with (-item);
      `checkp(av, "'{'h4}");
      wc[1] = -9;
      wc[2] = 9;
      wcv = wc.min;
      `checkp(wcv, "'{'hfffffff7}");
      wcv = wc.max;
      `checkp(wcv, "'{'h9}");
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
