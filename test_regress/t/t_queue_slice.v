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

module t;
  int pos = 1;
  int big = 32'sh7fff_ffff;
  int least = 32'sh8000_0000;
  longint wide = 64'sh1_0000_0000;
  byte neg = -1;
  longint wide_hi = 64'sd6442450943;
  longint wide_lo = -64'sd6442450943;
  bit [31:0] u31 = 32'h8000_0000;
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
