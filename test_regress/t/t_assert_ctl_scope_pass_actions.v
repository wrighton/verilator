// DESCRIPTION: Verilator: Selective concurrent assertion pass-action control
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module pass_leaf (
    input clk
);
  int vac_passes = 0;
  int nonvac_passes = 0;
  // Every attempt of the first property succeeds vacuously, of the second nonvacuously
  vac_check :
  assert property (@(posedge clk) 1'b0 |-> ##1 1'b1) vac_passes++;
  else `stop;
  nonvac_check :
  assert property (@(posedge clk) 1'b1 |-> ##1 1'b1) nonvac_passes++;
  else `stop;
endmodule

module t (
    input clk
);
  pass_leaf a (clk);
  pass_leaf b (clk);
  int cyc = 0;
  int phase = 0;
  int last_av = 0;
  int last_an = 0;
  int last_bv = 0;
  int last_bn = 0;

  // The oracle deliberately uses if/stop, never an assertion subject to control.
  task automatic check_deltas(int av, int an, int bv, int bn);
    `checkd(a.vac_passes - last_av, av);
    `checkd(a.nonvac_passes - last_an, an);
    `checkd(b.vac_passes - last_bv, bv);
    `checkd(b.nonvac_passes - last_bn, bn);
  endtask

  always @(negedge clk) begin
    cyc++;
    // Each phase lasts two cycles; only the second is checked, so an attempt
    // started before a control change cannot affect the checked cycle
    if (cyc >= 3 && cyc % 2 == 1) begin
      case (phase)
        0: begin
          check_deltas(1, 1, 1, 1);
          $assertcontrol(7, 1, 1, 0, a);  // PassOff, instance a only
        end
        1: begin
          check_deltas(0, 0, 1, 1);
          $assertcontrol(10, 1, 1, 0, a);  // NonvacuousOn, instance a only
        end
        2: begin
          check_deltas(0, 1, 1, 1);
          $assertcontrol(6, 1, 1, 0, a.vac_check);  // PassOn, one label
        end
        3: begin
          check_deltas(1, 1, 1, 1);
          $assertcontrol(7, 1, 1, 0, a.nonvac_check);  // PassOff, one label
        end
        default: begin
          check_deltas(1, 0, 1, 1);
          $write("*-* All Finished *-*\n");
          $finish;
        end
      endcase
      phase++;
    end
    last_av = a.vac_passes;
    last_an = a.nonvac_passes;
    last_bv = b.vac_passes;
    last_bn = b.nonvac_passes;
  end
endmodule
