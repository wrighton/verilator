// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An action of a procedural concurrent assertion that suspends, then leaves itself to the
// procedure by disable, break or continue
module t;
  bit clk = 0;
  always #5 clk = ~clk;

  // Test: disable of the procedure's block
  int disable_n = 0;
  always @(posedge clk) begin : blk
    assert property (0)
    else begin
      #1;
      ++disable_n;
      disable blk;
    end
  end

  // Test: break out of a loop of the procedure
  int break_n = 0;
  always @(posedge clk) begin
    for (int i = 0; i < 2; ++i) begin
      assert property (0)
      else begin
        #1;
        ++break_n;
        break;
      end
    end
  end

  // Test: continue of a loop of the procedure
  int continue_n = 0;
  always @(posedge clk) begin
    for (int i = 0; i < 2; ++i) begin
      assert property (0)
      else begin
        #1;
        ++continue_n;
        continue;
      end
    end
  end

  initial begin
    #101;
    `checkd(disable_n, 10);
    `checkd(break_n, 10);
    `checkd(continue_n, 20);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
