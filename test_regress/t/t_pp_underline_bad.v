// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2004 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // verilator_no_inline_module
  initial begin
    case (1'b1)  // synopsys_full_case
      1'b0: $stop;
      1'b1: $finish;
    endcase
    $stop;  // Should have failed
  end
  // synopsys_parallel_case
  // Below are not misspelled directives, so no warning
  // synopsys_translate_off
  // synopsys_translate_on

endmodule
