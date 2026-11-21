// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  bit x;
  initial begin
    // A null pass statement cannot be followed by 'else' (IEEE 1800-2023 A.6.3)
    assert (x); else $error("fail");
    assume (x); else $error("fail");
    assert #0 (x); else $error("fail");
    assume #0 (x); else $error("fail");
    assert final (x); else $error("fail");
    assume final (x); else $error("fail");
  end
  assert property (@(posedge clk) x); else $error("fail");
  assume property (@(posedge clk) x); else $error("fail");
endmodule
