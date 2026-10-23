// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

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

endmodule
