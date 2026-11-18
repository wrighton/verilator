// DESCRIPTION: Verilator: Selective assertion control
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
  empty_scope e ();
  int phase = 0;
  int last_as = 0;
  int last_ao = 0;
  int last_ac = 0;
  int last_bs = 0;
  int last_bo = 0;
  int last_bc = 0;
  int ctl_calls = 0;
  int type_calls = 0;
  int level_calls = 0;
  int level_value = 1;

  function automatic int control_type();
    ctl_calls++;
    return 4;
  endfunction
  function automatic int assertion_type();
    type_calls++;
    return 2;
  endfunction
  function automatic int levels();
    level_calls++;
    return level_value;
  endfunction

  task automatic check_counts(int asel, int aother, int achild, int bsel, int bother, int bchild);
    // The oracle deliberately uses if/stop, never an assertion subject to control.
    `checkd(a.selected_fails - last_as, asel);
    `checkd(a.other_fails - last_ao, aother);
    `checkd(a.child.selected_fails - last_ac, achild);
    `checkd(b.selected_fails - last_bs, bsel);
    `checkd(b.other_fails - last_bo, bother);
    `checkd(b.child.selected_fails - last_bc, bchild);
    last_as = a.selected_fails;
    last_ao = a.other_fails;
    last_ac = a.child.selected_fails;
    last_bs = b.selected_fails;
    last_bo = b.other_fails;
    last_bc = b.child.selected_fails;
  endtask

  always @(negedge clk) begin
    case (phase)
      0: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $assertoff(0, a);
      end
      1: begin
        check_counts(0, 0, 0, 1, 1, 1);
        $asserton;
      end
      2: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $assertoff(0, a.selected_check);
      end
      3: begin
        check_counts(0, 1, 1, 1, 1, 1);
        $asserton;
        $assertoff(1, a);
      end
      4: begin
        check_counts(0, 0, 1, 1, 1, 1);
        $asserton;
        $assertoff(2, a);
      end
      5: begin
        check_counts(0, 0, 0, 1, 1, 1);
        $asserton;
        $assertoff(0, a.selected_check, b.other_check);
      end
      6: begin
        check_counts(0, 1, 1, 1, 0, 1);
        $asserton;
        $assertcontrol(4, 1, 1, 0, a.selected_check);
      end
      7: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $assertcontrol(4, 2, 2, 0, a.selected_check);
      end
      8: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $assertcontrol(control_type(), assertion_type(), 1, levels(), a, b);
        `checkd(ctl_calls, 1);
        `checkd(type_calls, 1);
        `checkd(level_calls, 1);
      end
      9: begin
        check_counts(0, 0, 1, 0, 0, 1);
        $asserton;
        $assertoff(0, a.selected_check);
        $assertcontrol(1, 2, 1, 0, a.selected_check);
        $asserton;
      end
      10: begin
        check_counts(0, 1, 1, 1, 1, 1);
        $assertcontrol(2, 2, 1, 0, a.selected_check);
        $asserton;
      end
      11: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $assertoff;
      end
      12: begin
        check_counts(0, 0, 0, 0, 0, 0);
        $asserton;
      end
      13: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $assertfailoff(0, a.selected_check);
      end
      14: begin
        check_counts(0, 1, 1, 1, 1, 1);
        $assertfailon(0, a.selected_check);
      end
      15: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $assertkill(0, b);
      end
      16: begin
        check_counts(1, 1, 1, 0, 0, 0);
        $asserton;
      end
      17: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $assertoff(0, e);
      end
      18: begin
        check_counts(1, 1, 1, 1, 1, 1);
        $write("*-* All Finished *-*\n");
        $finish;
      end
      default: `stop;
    endcase
    phase++;
  end
endmodule

module empty_scope;
endmodule

module checked (
    input clk
);
  int selected_fails = 0;
  int other_fails = 0;
  leaf child (clk);
  always @(posedge clk) begin
    selected_check :
    assert (!clk)
    else selected_fails++;
    other_check :
    assert (!clk)
    else other_fails++;
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
