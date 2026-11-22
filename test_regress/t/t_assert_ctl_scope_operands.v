// DESCRIPTION: Verilator: Selective assertion control argument forms
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
  checked a (clk);
  checked b (clk);
  int cyc = 0;
  int phase = 0;
  int last_ao = 0;
  int last_ac = 0;
  int last_bo = 0;
  int last_bc = 0;
  byte lvl;

  // The oracle deliberately uses if/stop, never an assertion subject to control.
  task automatic check_deltas(int ao, int ac, int bo, int bc);
    `checkd(a.selected_fails - last_ao, ao);
    `checkd(a.child.selected_fails - last_ac, ac);
    `checkd(b.selected_fails - last_bo, bo);
    `checkd(b.child.selected_fails - last_bc, bc);
  endtask

  always @(negedge clk) begin
    cyc++;
    // Each phase lasts two cycles; only the second is checked
    if (cyc >= 3 && cyc % 2 == 1) begin
      case (phase)
        0: begin
          check_deltas(1, 1, 1, 1);
          // Omitted assertion and directive types default to all (IEEE 1800-2023 20.11)
          $assertcontrol(4,,, 0, a.selected_check);
        end
        1: begin
          check_deltas(0, 1, 1, 1);
          $asserton;
        end
        2: begin
          check_deltas(1, 1, 1, 1);
          $assertoff(4'd1, a);  // Unsigned narrow level: the scope itself only
        end
        3: begin
          check_deltas(0, 1, 1, 1);
          $asserton;
        end
        4: begin
          check_deltas(1, 1, 1, 1);
          lvl = 1;
          $assertoff(lvl, a);  // Signed narrow level
        end
        5: begin
          check_deltas(0, 1, 1, 1);
          $asserton;
        end
        6: begin
          check_deltas(1, 1, 1, 1);
          $assertoff(4'd0, a);  // Level zero: the scope and all instances below
        end
        7: begin
          check_deltas(0, 0, 1, 1);
          $asserton;
        end
        8: begin
          check_deltas(1, 1, 1, 1);
          // Each listed scope is selected at its own level, so a.child is selected
          $assertoff(1, a, a.child);
        end
        9: begin
          check_deltas(0, 0, 1, 1);
          $asserton;
        end
        10: begin
          check_deltas(1, 1, 1, 1);
          lvl = byte'(-cyc);
          $assertoff(lvl, a);  // A signed negative level selects no sites.
        end
        default: begin
          check_deltas(1, 1, 1, 1);
          $write("*-* All Finished *-*\n");
          $finish;
        end
      endcase
      phase++;
    end
    last_ao = a.selected_fails;
    last_ac = a.child.selected_fails;
    last_bo = b.selected_fails;
    last_bc = b.child.selected_fails;
  end
endmodule

module checked (
    input clk
);
  int selected_fails = 0;
  leaf child (clk);
  always @(posedge clk) begin
    selected_check :
    assert (!clk)
    else selected_fails++;
  end
endmodule

module leaf (
    input clk
);
  int selected_fails = 0;
  always @(posedge clk) begin
    selected_check :
    assert (!clk)
    else selected_fails++;
  end
endmodule
