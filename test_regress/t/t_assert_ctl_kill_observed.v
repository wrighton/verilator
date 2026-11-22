// DESCRIPTION: Verilator: Selective Kill flushes the matching deferred assertion report
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  int selected_sum = 0;
  int sibling_sum = 0;
  int value = 3;

  task automatic record_selected(input int payload);
    selected_sum += payload;
  endtask

  task automatic record_sibling(input int payload);
    sibling_sum += payload;
  endtask

  initial begin
    for (int i = 0; i < 2; ++i) begin
      selected :
      assert #0 (1'b1) record_selected(value);
      sibling :
      assert #0 (1'b1) record_sibling(value);
      if (i == 0) begin
        $assertkill(0, selected);
        $asserton(0, selected);
        value = 5;
      end
    end
    #1;
    `checkd(selected_sum, 5);
    `checkd(sibling_sum, 8);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
