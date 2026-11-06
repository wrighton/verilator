// DESCRIPTION: Verilator: Dotted reference that uses another dotted reference
// as the select expression
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package test_pkg;
  class foo;
    virtual function void visit();
      static int compiled_regex;
      compiled_regex = 1;
    endfunction

    function void end_v();
      visit.compiled_regex = 0;
    endfunction
  endclass
endpackage

// Static variables in named blocks of tasks and functions can be referenced
// hierarchically
module t;
  task st(input int si);
    begin : blk
      int ba;
      ba = si;
      begin : inner
        static int bi;
        bi = si + 1;
      end
    end
  endtask

  task ts(input int ti);
    fork : f
      int s;
      begin
        s = ti;
        begin : b
          int n;
          n = ti + 1;
        end
      end
    join
  endtask

  function automatic int af(input int fi);
    begin : fblk
      static int fs;
      fs = fi * 2;
    end
    return fi;
  endfunction

  initial begin
    st(3);
    `checkd(st.blk.ba, 3);
    `checkd(st.blk.inner.bi, 4);
    st(7);
    `checkd(st.blk.ba, 7);
    `checkd(st.blk.inner.bi, 8);
    ts(3);
    `checkd(ts.f.s, 3);
    `checkd(ts.f.b.n, 4);
    ts(7);
    `checkd(ts.f.s, 7);
    `checkd(ts.f.b.n, 8);
    `checkd(af(5), 5);
    `checkd(af.fblk.fs, 10);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
