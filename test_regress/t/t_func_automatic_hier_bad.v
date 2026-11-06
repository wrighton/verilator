// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  task automatic at(input int ai);
    int av;
    static int as;
    av = ai;
    as = ai;
    $display("%0d", at.av);  // OK: inside the task
  endtask

  function automatic int af(input int fi);
    int fv;
    fv = fi;
    return fv;
  endfunction

  task st(input int si);
    automatic int sav;
    int ssv;
    sav = si;
    ssv = si;
  endtask

  int w;
  assign w = at.av;  // BAD

  initial begin
    $display("%0d", at.av);  // BAD
    $display("%0d", at.ai);  // BAD
    $display("%0d", at.as);  // OK: static
    $display("%0d", af.fv);  // BAD
    $display("%0d", af.fi);  // BAD
    $display("%0d", st.sav);  // BAD
    $display("%0d", st.ssv);  // OK: static
    $display("%0d", st.si);  // OK: static
    $display("%0d", abt.blk.bv);  // BAD
    $display("%0d", abt.blk.bs);  // OK: static
    $display("%0d", ta.f.a);  // BAD
    $display("%0d", ta.f.s);  // OK: static
  end

  task automatic abt(input int ai);
    begin : blk
      int bv;
      static int bs;
      bv = ai;
      bs = ai;
    end
  endtask

  task automatic ta(input int ai);
    fork : f
      int a;
      static int s;
      begin
        a = ai;
        s = ai;
      end
    join
  endtask
endmodule
