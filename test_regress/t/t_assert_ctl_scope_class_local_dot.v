// DESCRIPTION: Verilator: Class local assertion control scopes named with several components
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // A task's block and a nested block are scopes within the class, named with '.'
  // (IEEE 1800-2023 23.6, 20.11)
  class C;
    static int task_failures = 0;
    static int block_failures = 0;
    static int other_failures = 0;
    task tk();
      begin : inner
        check :
        assert (1'b0)
        else task_failures++;
      end
    endtask
    function void blk();
      begin : outer
        begin : sub
          check :
          assert (1'b0)
          else block_failures++;
        end
        $assertoff(0, outer.sub);
      end
    endfunction
    function void off();
      $assertoff(0, tk.inner);
    endfunction
    task other();
      check :
      assert (1'b0)
      else other_failures++;
    endtask
  endclass
  initial begin
    automatic C c = new;
    c.off();
    c.tk();
    c.blk();
    c.blk();
    c.other();
    `checkd(C::task_failures, 0);
    `checkd(C::block_failures, 1);
    `checkd(C::other_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
