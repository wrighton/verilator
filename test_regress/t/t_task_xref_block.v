// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Hierarchical names, within a task or function, of its variables in its
// named blocks (IEEE 1800-2023 23.8)

module t;
  int r_blk, r_task, r_auto, r_func, r_sib, r_fsib;

  task tk;
    begin : a
      static int x;
      x = x + 5;
      begin : b
        r_blk = a.x;  // The enclosing block's
        r_task = tk.a.x;  // From the task's name
      end
    end
  endtask

  // A static variable of a sibling block, the same from anywhere (IEEE 1800-2023 6.21)
  task stk;
    begin : a1
      static int s = 3;
      s = s + 1;
    end
    begin : b1
      r_sib = a1.s;
    end
  endtask

  function int sf;
    begin : fa
      static int q = 9;
    end
    begin : fb
      return fa.q;
    end
  endfunction

  task automatic tka;
    begin : c
      int y;
      y = 7;
      begin : d
        r_auto = c.y;  // The current activation's
      end
    end
  endtask

  function automatic int fn(int v);
    begin : e
      int z;
      z = v * 2;
      return e.z;
    end
  endfunction

  initial begin
    tk();
    tk();
    tka();
    r_func = fn(21);
    stk();
    stk();
    r_fsib = sf();
    `checkd(r_blk, 10);
    `checkd(r_task, 10);
    `checkd(r_auto, 7);
    `checkd(r_func, 42);
    `checkd(r_sib, 5);
    `checkd(r_fsib, 9);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
