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
      q3[5 : 6] = '{9, 9};
      `checkh(q3[2], 3);
      q3[1 : 5] = '{7, 8};
      `checkh(q3[1], 7);
      `checkh(q3[2], 8);
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
      end
      d = '{20, 21, 22, 23};
      d = d[1:2];
      `checkp(d, "'{'h15, 'h16}");
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

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
