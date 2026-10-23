// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilator lint_off IEEEMAYDEPRECATE

module t (
    input a
);

  int n;

  task automatic tsk;
  endtask

  always_comb begin
    assert final (a) else n = 1;  // BAD
    assert #0 (a) n++;  // BAD
    assume final (a) else begin  // BAD
      $display("fail");
    end
    cover #0 (a) if (a) $display("pass");  // BAD
    assert final (a) else case (a) default: $display("fail"); endcase  // BAD
    assert final (a) else while (n < 2) $display("fail");  // BAD
    assert final (a) else repeat (2) $display("fail");  // BAD
    // Subroutine calls and simple immediate assertions are fine
    assert final (a) $display("pass"); else $error("fail");
    assert #0 (a) tsk(); else;
    assert (a) else n = 2;
  end

  event ev;
  int q[2];
  logic r;
  wire w;
  initial begin
    assert final (a) else foreach (q[i]) $display(i);  // BAD
    assert final (a) else ->ev;  // BAD
    assert final (a) else #1 $display("fail");  // BAD
    assert final (a) else @(ev) $display("fail");  // BAD
    assert final (a) else wait (n == 1) $display("fail");  // BAD
    assert final (a) else wait fork;  // BAD
    assert final (a) else disable fork;  // BAD
    assert final (a) else force w = 1'b1;  // BAD
    assert final (a) else release w;  // BAD
    assert final (a) else assign r = 1'b1;  // BAD
    assert final (a) else deassign r;  // BAD
    assert final (a) else assert (n == 0);  // BAD
    assert final (a) else randcase 1: $display("fail"); endcase  // BAD
    assert final (a) else randsequence(main) main: {$display("fail");}; endsequence  // BAD
    begin : blk
      assert final (a) else disable blk;  // BAD
    end
  end

  task automatic t_return;
    assert final (a) else return;  // BAD
  endtask

endmodule
