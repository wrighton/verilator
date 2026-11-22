// DESCRIPTION: Verilator: Global assertion Off preserves a running NFA attempt
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t;
  bit clk = 0;
  always #1 clk = ~clk;
  int cyc = 0;
  int failures = 0;

`ifdef SEED_CONTROL
  // An unrelated, unexecuted scope control must not change global Off.
  other :
  assert property (@(posedge clk) 1'b1);
  initial if (1'b0) $assertoff(0, t.other);
`endif

  check_late :
  assert property (@(posedge clk) (cyc == 2 || cyc == 5) |-> ##2 1'b0)
  else failures++;

  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    case (cyc)
      3: $assertoff;
      6: begin
        `checkd(failures, 1);
      end
      9: begin
        // The first attempt completed; no new attempt started with checks off.
        `checkd(failures, 1);
        $write("*-* All Finished *-*\n");
        $finish;
      end
      default: begin
      end
    endcase
  end
endmodule
