// DESCRIPTION: Verilator: Scoped concurrent assertion control
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t (
    input clk
);
  int cyc = 0;
  late_check a (
      clk,
      cyc
  );
  late_check b (
      clk,
      cyc
  );
  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    case (cyc)
      3: $assertoff(0, a.check_late);
      6: begin
        // The selected site uses the same outcome gating as a global Off.
        `checkd(a.failures, 0);
        `checkd(b.failures, 1);
        $asserton(0, a);
      end
      8: begin
        $assertkill(0, a.check_late);
        $asserton(0, a.check_late);
      end
      11: begin
        // Kill aborts the selected attempt, not the sibling's attempt.
        `checkd(a.failures, 0);
        `checkd(b.failures, 2);
        $write("*-* All Finished *-*\n");
        $finish;
      end
      default: begin
      end
    endcase
  end
endmodule

module late_check (
    input clk,
    input int cyc
);
  int failures = 0;
  check_late :
  assert property (@(posedge clk) (cyc == 2 || cyc == 7) |-> ##2 1'b0)
  else failures++;
endmodule
