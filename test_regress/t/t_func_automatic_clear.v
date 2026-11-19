// DESCRIPTION: Verilator: Test automatic function variables lifetime
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Augustin Fabre
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Bug5747: Make sure that a variable with automatic storage is freshly
// allocated when entering the function.

module t;
  function automatic int ts_queue();
    static int qs[$];
    qs.push_back(0);
    // $display("  qs: %p", qs);
    return qs.size();
  endfunction

  function automatic int t_queue();
    int q[$];
    q.push_back(0);
    // $display("  q: %p", q);
    return q.size();
  endfunction

  function automatic int t_scalar();
    int x;
    ++x;
    return x;
  endfunction

  typedef struct {int y;} y_t;

  function automatic int t_struct();
    y_t y;
    ++y.y;
    return y.y;
  endfunction

  function automatic string t_string();
    string x;
    x = {x, "s"};
    return x;
  endfunction

  class ClsZ;
    int z;
  endclass

  function automatic int t_class();
    ClsZ z = new();
    ++z.z;
    return z.z;
  endfunction

  typedef string dyn_t[];
  function automatic dyn_t t_dyn();
    dyn_t x;
    x = {x, "s"};
    return x;
  endfunction

  typedef string assoc_t[int];
  function automatic assoc_t t_assoc();
    static int ins = 0;
    assoc_t x;
    ins = ins + 1;
    x[ins] = "s";
    return x;
  endfunction

  typedef string wild_t [*];
  function automatic wild_t t_wild();
    static int ins = 0;
    wild_t x;
    ins = ins + 1;
    x[ins] = "s";
    return x;
  endfunction

  typedef int unpack_t[8];
  function automatic unpack_t t_unpack();
    static int ins = 0;
    unpack_t x;
    ins = ins + 1;
    x[ins] = ins;
    return x;
  endfunction

  // Calls of a function inlined in a class method, made recursively from the function
  class ClsName;
    function void name(int n, output string s);
      t_describe(this, n, s);
    endfunction
  endclass

  function automatic void t_describe(ClsName c, int n, output string s);
    string inner;
    s = $sformatf("n%0d", n);
    if (n > 0) begin
      c.name(n - 1, inner);
      s = {s, ":", inner, ":", s};
    end
  endfunction

  // Calls of a function inlined in a loop of a class method
  class ClsLoop;
    function string run();
      string r;
      for (int i = 0; i < 3; ++i) r = {r, t_string()};
      return r;
    endfunction
  endclass

  // A call of a function inlined in a class method, after all its paths have returned
  class ClsDead;
    int m_x = 1;
    function int pick(int k);
      case (k)
        1: return 1;
        default: return 2;
      endcase
      if (t_string() == "s") m_x = 5;
      return 0;
    endfunction
  endclass

  // A call of a function inlined in a wait condition of a class task
  function automatic int t_twice(int n);
    int r;
    r = 2 * n;
    return r;
  endfunction

  class ClsWait;
    int m_x;
    task wait_x();
      wait (m_x > 0 && t_twice(m_x) == 6);
    endtask
  endclass

  task automatic t_wait_inlined();
    ClsWait c = new;
    fork
      c.wait_x();
      begin
        #1 c.m_x = 3;
      end
    join
    `checkh(c.m_x, 3);
  endtask

  // Calls of a task inlined in a class task, running at the same time on one object
  task automatic t_delayed_copy(string in, int n, output string out, output int m);
    #1;
    out = in;
    m = n;
  endtask

  class ClsCopy;
    task copy(string in, int n, output string out, output int m);
      t_delayed_copy(in, n, out, m);
    endtask
  endclass

  task automatic t_copy_concurrent();
    ClsCopy c = new;
    string out1, out2;
    int m1, m2;
    fork
      c.copy("a", 2, out1, m1);
      c.copy("b", 1, out2, m2);
    join
    `checks(out1, "a");
    `checks(out2, "b");
    `checkh(m1, 2);
    `checkh(m2, 1);
  endtask

  // =======================

  function automatic void main();
    for (int i = 0; i < 3; ++i) begin
      int qn = ts_queue();
      int qo = ts_queue();
      `checkh(qn, i * 2 + 1);
      `checkh(qo, i * 2 + 2);
    end

    for (int i = 0; i < 3; ++i) begin
      int qn = t_queue();
      `checkh(qn, 1);
    end

    for (int i = 0; i < 3; ++i) begin
      int x = t_scalar();
      `checkh(x, 1);
    end

    for (int i = 0; i < 3; ++i) begin
      int y = t_struct();
      `checkh(y, 1);
    end

    for (int i = 0; i < 3; ++i) begin
      int z = t_class();
      `checkh(z, 1);
    end

    for (int i = 0; i < 3; ++i) begin
      string z = t_string();
      `checks(z, "s");
    end

    for (int i = 0; i < 3; ++i) begin
      dyn_t z = t_dyn();
      `checkh(z.size(), 1);
    end

    for (int i = 0; i < 3; ++i) begin
      assoc_t z = t_assoc();
      `checkh(z.size(), 1);
    end

    for (int i = 0; i < 3; ++i) begin
      wild_t z = t_wild();
      `checkh(z.size(), 1);
    end

    for (int i = 0; i < 3; ++i) begin
      int cnt;
      unpack_t z = t_unpack();
      cnt = 0;
      for (int j = 0; j < $high(z); ++j) begin
        if (z[j] != 0) cnt = cnt + 1;
      end
      `checkh(cnt, 1);
    end

    begin
      ClsDead c = new;
      `checkh(c.pick(3), 2);
      `checkh(c.m_x, 1);
    end

    begin
      ClsLoop c = new;
      `checks(c.run(), "sss");
    end

    begin
      ClsName c = new;
      string s;
      c.name(2, s);
      `checks(s, "n2:n1:n0:n1:n2");
    end
  endfunction

  initial begin
    main();
    t_copy_concurrent();
    t_wait_inlined();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
