// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

function automatic int f(int m);
  return m;
endfunction

function automatic int counted_bound(int m, ref int calls);
  ++calls;
  return m;
endfunction

module t;
  int pos = 1;
  int big = 32'sh7fff_ffff;
  int least = 32'sh8000_0000;
  longint wide = 64'sh1_0000_0000;
  byte neg = -1;
  longint wide_hi = 64'sd6442450943;
  longint wide_lo = -64'sd6442450943;
  bit [31:0] u31 = 32'h8000_0000;
  longint wide_one = 1;
  localparam longint K0 = 0;
  localparam longint K1 = 1;
  localparam longint KHI = 64'sd6442450943;
  localparam bit [63:0] KU1 = '1;
  localparam bit [63:0] KU2 = 64'hffff_ffff_ffff_fffe;
  int calls = 0;
  function int pos_call();
    ++calls;
    return pos;
  endfunction

  initial begin
    typedef string q_t[$];
    q_t q;
    string v;
    int i;
    int qi[$:5];
    int ri[$];

    q.push_front("non-empty");
    i = q.size();
    `checkh(i, 1);
    `checkp(q, "'{\"non-empty\"}");

    q = '{};
    i = q.size();
    `checkh(i, 0);

    q = '{"q"};
    `checkp(q, "'{\"q\"}");

    q = {};
    i = q.size();
    `checkh(i, 0);

    q = '{"q", "b", "c", "d", "e", "f"};
    if (q[0] !== "q") $stop;
    `checkp(q, "'{\"q\", \"b\", \"c\", \"d\", \"e\", \"f\"}");

    q = {"q", "b", "c", "d", "e", "f"};
    `checkp(q, "'{\"q\", \"b\", \"c\", \"d\", \"e\", \"f\"}");

    q.delete(1);
    v = q[1];
    `checks(v, "c");
    `checkp(q, "'{\"q\", \"c\", \"d\", \"e\", \"f\"}");

    q.insert(0, "ins0");
    q.insert(2, "ins2");
    v = q[0];
    `checks(v, "ins0");
    v = q[2];
    `checks(v, "ins2");
    `checkp(q, "'{\"ins0\", \"q\", \"ins2\", \"c\", \"d\", \"e\", \"f\"}");

    // Slicing
    q = '{"q", "b", "c", "d", "e", "f"};
    q = q[-1:0];
    `checkp(q, "'{\"q\"}");
    q = '{"q", "b", "c", "d", "e", "f"};
    q = q[2:3];
    `checkp(q, "'{\"c\", \"d\"}");
    q = '{"q", "b", "c", "d", "e", "f"};
    q = q[3:$];
    `checkp(q, "'{\"d\", \"e\", \"f\"}");
    q = q[$:$];
    `checkp(q, "'{\"f\"}");

    // Similar using implied notation
    q = '{"f"};
    q = {q, "f1"};  // push_front
    q = {q, "f2"};  // push_front
    q = {"b1", q};  // push_back
    q = {"b2", q};  // push_back
    `checkp(q, "'{\"b2\", \"b1\", \"f\", \"f1\", \"f2\"}");

    q = {q[0], q[2:$]};  // delete element 1
    `checkp(q, "'{\"b2\", \"f\", \"f1\", \"f2\"}");

    q = {"a", "b"};
    q = {q, q};
    `checkp(q, "'{\"a\", \"b\", \"a\", \"b\"}");

    begin
      static string ai[$] = '{"Foo", "Bar"};
      q = ai;  // Copy
      i = q.size();
      `checkh(i, 2);
      v = q.pop_front();
      `checks(v, "Foo");
      v = q.pop_front();
      `checks(v, "Bar");
      q = '{"BB", "CC"};  // Note '{} not {}
      v = q.pop_front();
      `checks(v, "BB");
      v = q.pop_front();
      `checks(v, "CC");
      q = {"BB", "CC"};  // Note {} not '{}
      v = q.pop_front();
      `checks(v, "BB");
      v = q.pop_front();
      `checks(v, "CC");
    end

    begin
      qi.push_back(0);
      qi.push_back(1);
      qi.push_back(2);
      qi.push_back(3);
      qi.push_back(4);
      qi.push_back(5);

      // Assignment to unsized queue from sized queue
      ri = qi[2 : 4];
      `checkh(ri.size, 3);
      ri = qi[4 : 2];
      `checkh(ri.size, 0);
      ri = qi[2 : 2];
      `checkh(ri.size, 1);
      ri = qi[-2 : 2];  // 2 - 0 + 1 = 3
      `checkh(ri.size, 3);
      ri = qi[2 : 10];  // 5 - 2 + 1 = 4
      `checkh(ri.size, 4);
      ri = qi[6 : 7];  // Outside the queue
      `checkh(ri.size, 0);
      ri = qi[0 : -1];
      `checkh(ri.size, 0);
      ri = qi[0 : $ - 7];
      `checkh(ri.size, 0);
      ri = qi[$ - 8 : $ - 7];
      `checkh(ri.size, 0);
      qi.delete();
      ri = qi[0 : 1];
      `checkh(ri.size, 0);
      qi = '{0, 1, 2, 3, 4, 5};
    end

    // Slices lying outside the queue are empty (#7355)
    begin
      automatic int one[$] = '{1};
      int none[$];
      int res[$];
      res = one[1 : $];
      `checkh(res.size, 0);
      res = one[2 : 3];
      `checkh(res.size, 0);
      res = one[0 : 0];
      `checkh(res.size, 1);
      res = none[0 : 0];
      `checkh(res.size, 0);
      res = none[0 : $];
      `checkh(res.size, 0);
      one = one[1 : $];
      `checkh(one.size, 0);
    end

    begin
      automatic int q3[$] = '{1, 2, 3};
      automatic int res[$];
      res = q3[0 : $ - 5];
      `checkh(res.size, 0);
      res = q3[$ - 5 : 1];
      `checkh(res.size, 2);
      res = q3[$ - 1 : $];
      `checkh(res.size, 2);
      res = q3[-3 : -1];
      `checkh(res.size, 0);
      q3[1 : 5] = '{7, 8};
      `checkh(q3[1], 7);
      `checkh(q3[2], 8);
    end

    begin
      // A slice ending at $+1, of the size assigned, writes it and appends its last element
      automatic int qa[$] = '{1, 2};
      automatic int qe[$];
      qa[1:2] = '{10, 11};
      `checkp(qa, "'{'h1, 'ha, 'hb}");
      qa[3:3] = '{12};
      `checkp(qa, "'{'h1, 'ha, 'hb, 'hc}");
      qe[0:0] = '{9};
      `checkp(qe, "'{'h9}");
      qa = '{1, 2};
      qa[1:2] = qa;
      `checkp(qa, "'{'h1, 'h1, 'h2}");
    end

    begin
      // Assignment from unsized to sized
      ri = '{1, 2, 3, 4, 5, 6, 7, 8, 9};
      qi = ri;
      `checkh(qi.size, 6);
    end

    // Indexed part-selects and slices of queues and dynamic arrays
    begin
      typedef int d_t[];
      d_t d;
      int iq[$];
      iq = '{10, 11, 12, 13};
      d = '{20, 21, 22, 23};
      for (int j = 0; j < 3; ++j) begin
        ri = iq[j+:2];
        `checkp(ri, $sformatf("'{'h%0x, 'h%0x}", 10 + j, 11 + j));
        ri = iq[j+1-:2];
        `checkp(ri, $sformatf("'{'h%0x, 'h%0x}", 10 + j, 11 + j));
        ri = d[j+:2];
        `checkp(ri, $sformatf("'{'h%0x, 'h%0x}", 20 + j, 21 + j));
      end
      d = d[pos-:2];
      `checkp(d, "'{'h14, 'h15}");
      begin
        // Narrow positions; '-:' going below the first element is clamped to it
        bit [2:0] p3;
        byte sp;
        p3 = 0;
        sp = 2;
        ri = iq[p3-:2];
        `checkp(ri, "'{'ha}");
        ri = iq[sp-:2];
        `checkp(ri, "'{'hb, 'hc}");
        ri = d[p3-:2];
        `checkp(ri, "'{'h0, 'h14}");
      end
      d = '{20, 21, 22, 23};
      d = d[1:2];
      `checkp(d, "'{'h15, 'h16}");
      // A dynamic array slice keeps its size, reading the default value past either end
      d = '{20, 21};
      ri = d[1:2];
      `checkp(ri, "'{'h15, 'h0}");
      ri = d[pos+:2];
      `checkp(ri, "'{'h15, 'h0}");
      begin
        int p0;
        p0 = 0;
        ri = d[p0-:2];
        `checkp(ri, "'{'h0, 'h14}");
      end
      ri = d[big+:2];
      `checkp(ri, "'{'h0, 'h0}");
      ri = d[big-1+:2];
      `checkp(ri, "'{'h0, 'h0}");
      ri = d[least-:2];
      `checkp(ri, "'{'h0, 'h0}");
      // A position that does not fit in 32 bits selects no element, a narrow one keeps its sign
      d = '{20, 21};
      ri = d[wide+:2];
      `checkp(ri, "'{'h0, 'h0}");
      ri = d[wide+1-:2];
      `checkp(ri, "'{'h0, 'h0}");
      ri = d[64'sh1_0000_0000:64'sh1_0000_0001];
      `checkp(ri, "'{'h0, 'h0}");
      ri = d[64'h1_0000_0000:64'h1_0000_0001];
      `checkp(ri, "'{'h0, 'h0}");
      // Constant positions without a 64-bit value give no constant size
      ri = d[0:64'hffff_ffff_ffff_ffff];
      `checkp(ri, "'{'h14, 'h15}");
      ri = d[neg+:2];
      `checkp(ri, "'{'h0, 'h14}");
      ri = iq[wide+:2];
      `checkp(ri, "'{}");
      // A queue slice bound past either end is limited to the queue
      iq = '{10, 11, 12};
      ri = iq[0:wide_hi];
      `checkp(ri, "'{'ha, 'hb, 'hc}");
      ri = iq[wide_lo:1];
      `checkp(ri, "'{'ha, 'hb}");
      ri = iq[wide_hi:wide_hi];
      `checkp(ri, "'{}");
      // A bound relative to '$' may be wider than '$'
      // verilator lint_off WIDTHEXPAND
      ri = iq[$-wide_hi:$];
      `checkp(ri, "'{'ha, 'hb, 'hc}");
      ri = iq[$-wide_lo:$];
      `checkp(ri, "'{}");
      ri = iq[$-wide:$];
      `checkp(ri, "'{'ha, 'hb, 'hc}");
      ri = iq[$-wide_one:$];
      `checkp(ri, "'{'hb, 'hc}");
      ri = iq[wide_lo:$-wide_one];
      `checkp(ri, "'{'ha, 'hb}");
      ri = iq[0:$-wide_hi];
      `checkp(ri, "'{}");
      ri = iq[0:$-wide_lo];
      `checkp(ri, "'{'ha, 'hb, 'hc}");
      ri = iq[$-wide_hi:$-wide_one];
      `checkp(ri, "'{'ha, 'hb}");
      `checkh(iq[$-wide_hi], 0);
      `checkh(iq[$-wide_lo], 0);
      `checkh(iq[$-wide], 0);
      `checkh(iq[$-wide_one], 'hb);
      iq[$-wide_one] = 99;
      `checkp(iq, "'{'ha, 'h63, 'hc}");
      iq[$-wide_hi] = 98;
      iq[$-wide_lo] = 97;
      `checkp(iq, "'{'ha, 'h63, 'hc}");
      iq[$-wide_one:$] = '{7, 8};
      `checkp(iq, "'{'ha, 'h7, 'h8}");
      iq[$-wide_hi:$] = '{1, 2, 3};
      `checkp(iq, "'{'h1, 'h2, 'h3}");
      // verilator lint_on WIDTHEXPAND
      // A 32-bit bound relative to '$' needs no extension
      iq = '{10, 11, 12};
      ri = iq[$-pos:$];
      `checkp(ri, "'{'hb, 'hc}");
      ri = iq[$-big:$];
      `checkp(ri, "'{'ha, 'hb, 'hc}");
      `checkh(iq[$-big], 0);
      // An indexed part-select may have a base relative to '$': 'q[$-k+:w]' is
      // 'q[$-k:$-k+w-1]', and 'q[$-k-:w]' is 'q[$-k-w+1:$-k]'
      iq = '{10, 11, 12, 13};
      ri = iq[$-:2];
      `checkp(ri, "'{'hc, 'hd}");
      ri = iq[$+:1];
      `checkp(ri, "'{'hd}");
      ri = iq[$+:2];
      `checkp(ri, "'{'hd}");
      ri = iq[$-1+:2];
      `checkp(ri, "'{'hc, 'hd}");
      ri = iq[$-2+:2];
      `checkp(ri, "'{'hb, 'hc}");
      ri = iq[$-1-:2];
      `checkp(ri, "'{'hb, 'hc}");
      ri = iq[$-pos-:3];
      `checkp(ri, "'{'ha, 'hb, 'hc}");
      begin
        int k;
        k = 3;
        ri = iq[$-k+:2];
        `checkp(ri, "'{'ha, 'hb}");
        k = 4;
        ri = iq[$-k+:2];
        `checkp(ri, "'{'ha}");
        k = 10;
        ri = iq[$-k+:2];
        `checkp(ri, "'{}");
        k = -1;
        ri = iq[$-k-:2];
        `checkp(ri, "'{'hd}");
        ri = iq[$-k+:2];
        `checkp(ri, "'{}");
      end
      // verilator lint_off WIDTHEXPAND
      ri = iq[$-wide_one+:2];
      `checkp(ri, "'{'hc, 'hd}");
      ri = iq[$-wide_one-:2];
      `checkp(ri, "'{'hb, 'hc}");
      ri = iq[$-wide+:2];
      `checkp(ri, "'{}");
      ri = iq[$-wide_hi+:2];
      `checkp(ri, "'{}");
      ri = iq[$-wide_lo-:2];
      `checkp(ri, "'{}");
      // verilator lint_on WIDTHEXPAND
      // A constant offset of 64 bits
      // verilator lint_off WIDTHEXPAND
      ri = iq[$-K0+:2];
      `checkp(ri, "'{'hd}");
      ri = iq[$-K0-:2];
      `checkp(ri, "'{'hc, 'hd}");
      ri = iq[$-K1+:2];
      `checkp(ri, "'{'hc, 'hd}");
      ri = iq[$-K1-:3];
      `checkp(ri, "'{'ha, 'hb, 'hc}");
      ri = iq[$-KHI+:2];
      `checkp(ri, "'{}");
      ri = iq[$-KHI-:2];
      `checkp(ri, "'{}");
      // An unsigned offset near 2**64 is far past the front, also adding the width of '-:'
      ri = iq[$-KU1-:3];
      `checkp(ri, "'{}");
      ri = iq[$-KU1+:2];
      `checkp(ri, "'{}");
      ri = iq[$-KU2-:3];
      `checkp(ri, "'{}");
      ri = iq[$-KU2+:2];
      `checkp(ri, "'{}");
      // verilator lint_on WIDTHEXPAND
      // The base is evaluated once
      ri = iq[$-pos_call()+:2];
      `checkp(ri, "'{'hc, 'hd}");
      `checkh(calls, 1);
      ri = iq[$-pos_call()-:2];
      `checkp(ri, "'{'hb, 'hc}");
      `checkh(calls, 2);
      // A write follows the rules of the slice it is equivalent to
      iq[$-1+:2] = '{7, 8};
      `checkp(iq, "'{'ha, 'hb, 'h7, 'h8}");
      iq[$-:2] = '{5, 6};
      `checkp(iq, "'{'ha, 'hb, 'h5, 'h6}");
      iq[$-pos_call()-:2] = '{3, 4};
      `checkp(iq, "'{'ha, 'h3, 'h4, 'h6}");
      `checkh(calls, 3);
      // verilator lint_off WIDTHEXPAND
      iq[$-K1-:3] = '{1, 2, 3};
      `checkp(iq, "'{'h1, 'h2, 'h3, 'h6}");
      iq[$-K0-:2] = '{4, 5};
      `checkp(iq, "'{'h1, 'h2, 'h4, 'h5}");
      iq[$-K1+:2] = '{6, 7};
      `checkp(iq, "'{'h1, 'h2, 'h6, 'h7}");
      iq[$-K0+:1] = '{3};
      `checkp(iq, "'{'h1, 'h2, 'h6, 'h3}");
      // verilator lint_on WIDTHEXPAND
      iq = '{10, 3, 4, 6};
      begin
        int k;
        // Ending at $+1 with all elements assigned appends the last
        k = -1;
        iq[$-k+:1] = '{9};
        `checkp(iq, "'{'ha, 'h3, 'h4, 'h6, 'h9}");
        iq[$+:2] = '{1, 2};
        `checkp(iq, "'{'ha, 'h3, 'h4, 'h6, 'h1, 'h2}");
      end
      calls = 0;
      iq = '{10, 11, 12};
      // A slice with an X or Z position selects no element
      ri = iq[4'bx000:1];
      `checkp(ri, "'{}");
      ri = iq[0:4'bx001];
      `checkp(ri, "'{}");
      // verilator lint_off WIDTHEXPAND
      ri = iq[$-4'bx001:$];
      `checkp(ri, "'{}");
      ri = iq[1:$-4'bx000];
      `checkp(ri, "'{}");
      // verilator lint_on WIDTHEXPAND
      iq = '{11, 22, 33};
      ri = iq[1:wide];
      `checkp(ri, "'{'h16, 'h21}");
      // A dynamic array slice of variable size is limited to the array too
      ri = d[0:wide_hi];
      `checkp(ri, "'{'h14, 'h15}");
      ri = d[wide_lo:1];
      `checkp(ri, "'{'h14, 'h15}");
      ri = d[pos:wide];
      `checkp(ri, "'{'h15}");
      // So is an unsigned 32-bit one past the int range
      ri = iq[u31:5];
      `checkp(ri, "'{}");
      ri = iq[1:u31];
      `checkp(ri, "'{'h16, 'h21}");
      ri = d[1:u31];
      `checkp(ri, "'{'h15}");
      ri = d[u31+:2];
      `checkp(ri, "'{'h0, 'h0}");
      `checkh(iq[u31], 0);
      `checkh(d[u31], 0);
      iq = '{10, 11, 12, 13};
      d[wide+:2] = '{1, 2};
      `checkp(d, "'{'h14, 'h15}");
      // A slice of variable size is limited to the array
      ri = d[pos-1:pos+999999999];
      `checkp(ri, "'{'h14, 'h15}");
      // Writing a dynamic array slice skips the indexes outside the array
      d = '{11, 22, 33};
      d[pos-:3] = '{50, 51, 52};
      `checkp(d, "'{'h33, 'h34, 'h21}");
      d[2+:3] = '{60, 61, 62};
      `checkp(d, "'{'h33, 'h34, 'h3c}");
      d[1:3] = '{70, 71, 72};
      `checkp(d, "'{'h33, 'h46, 'h47}");
      d[-1:1] = '{80, 81, 82};
      `checkp(d, "'{'h51, 'h52, 'h47}");
      q = '{"a", "b", "c"};
      q = q[pos+:2];
      `checkp(q, "'{\"b\", \"c\"}");
      // The position is evaluated once
      ri = iq[pos_call()+:2];
      `checkp(ri, "'{'hb, 'hc}");
      `checkh(calls, 1);
      iq[pos_call()+:2] = '{1, 2};
      `checkp(iq, "'{'ha, 'h1, 'h2, 'hd}");
      `checkh(calls, 2);
      d = '{20, 21, 22, 23};
      d[pos_call()-:2] = '{3, 4};
      `checkp(d, "'{'h3, 'h4, 'h16, 'h17}");
      `checkh(calls, 3);
    end

    // Queue bounds are runtime expressions, including function calls.
    begin
      typedef int int_queue_t[$];
      int_queue_t q;
      int_queue_t result;
      int m;
      int calls;
      for (m = 1; m <= 4; ++m) begin
        q = '{0, 1, 2, 3, 4};
        q = q[0:f(m) - 1];
        `checkh(q.size(), m);
        foreach (q[i]) `checkh(q[i], i);
      end
      q = '{0, 1, 2, 3, 4};
      calls = 0;
      result = q[counted_bound(1, calls):counted_bound(3, calls)];
      `checkh(calls, 2);
      `checkp(result, "'{'h1, 'h2, 'h3}");
      result = q[$ - counted_bound(2, calls):$ - counted_bound(1, calls)];
      `checkh(calls, 4);
      `checkp(result, "'{'h2, 'h3}");
      q = q[0:counted_bound(3, calls) - 1];
      `checkh(calls, 5);
      `checkp(q, "'{'h0, 'h1, 'h2}");
      q[counted_bound(0, calls):counted_bound(1, calls)] = '{8, 9};
      `checkh(calls, 7);
      `checkp(q, "'{'h8, 'h9, 'h2}");
    end

    // Ordinary packed and fixed-array slices still evaluate constant functions.
    begin
      bit [14:0] word;
      int source[3:1];
      int result[2];
      word = 15'h1a5;
      source = '{31, 21, 11};
      `checkh(word[f(4):f(1)], 4'h2);
      result = source[f(3):f(2)];
      `checkh(result[0], 31);
      `checkh(result[1], 21);
    end

    begin
      // A stream is written from the left of a slice, and the rest of it with zeros
      automatic byte bd[] = '{1, 2, 3, 4};
      automatic byte bq[$] = '{1, 2, 3, 4, 5};
      automatic int id[] = '{1, 2, 3};
      bd[1:3] = {>>{16'haabb}};
      `checkp(bd, "'{'h1, 'haa, 'hbb, 'h0}");
      bd[-1:1] = {>>{8'h77}};
      `checkp(bd, "'{'h0, 'h0, 'hbb, 'h0}");
      bq[1:3] = {>>{8'hcc}};
      `checkp(bq, "'{'h1, 'hcc, 'h0, 'h0, 'h5}");
      bq[pos+:2] = {<<8{16'hddee}};
      `checkp(bq, "'{'h1, 'hee, 'hdd, 'h0, 'h5}");
      bq[1:$-1] = {>>{16'hff11}};
      `checkp(bq, "'{'h1, 'hff, 'h11, 'h0, 'h5}");
      id[0:2] = {>>{16'h1234}};
      `checkp(id, "'{'h12340000, 'h0, 'h0}");
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
