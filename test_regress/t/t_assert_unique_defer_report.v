// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Violations of unique, unique0 and priority checks that persist to the Observed region of their
// time step are reported once, after the other output of the time step, with the scope, time and
// values of the last check of their process (IEEE 1800-2023 12.4.2.1, 12.5.3.1)
module t;
  // A process executed again with a still violating value reports only its last check
  logic [30:0] re_v = 31'd1;
  always_comb begin : reexecuted
    unique case (re_v) inside
      [31'd1 : 31'd5]: ;
      [31'd4 : 31'd9]: ;
    endcase
  end
  initial begin
    #1;
    re_v = 31'd4;
    re_v <= 31'd5;
    $display("[%0t] reexecuted: before the Observed region", $time);
    #1;
    re_v = 31'd1;
  end

  initial begin : unique_if_overlap
    logic a, b;
    int n;
    #2;
    a = 1'b1;
    b = 1'b1;
    unique if (a) n = 1;
    else if (b) n = 2;
    $display("[%0t] unique_if_overlap: after the check", $time);
  end

  initial begin : unique_if_none
    logic [6:0] v;
    int n;
    #3;
    v = 7'd3;
    unique if (v == 7'd1) n = 1;
    else if (v == 7'd2) n = 2;
  end

  initial begin : unique0_if_overlap
    logic a, b;
    int n;
    #4;
    a = 1'b1;
    b = 1'b1;
    unique0 if (a) n = 1;
    else if (b) n = 2;
  end

  // The reported value is the one checked, not a later one
  initial begin : unique_case_none
    logic [30:0] v;
    #5;
    v = 31'd9;
    unique case (v)
      31'd1: $display("[%0t] unique_case_none: 1", $time);
      31'd2: $display("[%0t] unique_case_none: 2", $time);
    endcase
    v = 31'd1;
  end

  initial begin : unique0_case_multiple
    logic [14:0] v;
    #6;
    v = 15'h1234;
    unique0 case (1'b1)
      v[2]: $display("[%0t] unique0_case_multiple: first item", $time);
      v[4]: $display("[%0t] unique0_case_multiple: second item", $time);
    endcase
  end

  // Each iteration of a loop reports its own violation
  logic [2:0] loop_a = 3'b000, loop_b = 3'b000;
  always_comb begin : loop
    for (int j = 0; j < 3; j++)
      unique0 if (loop_a[j]) ;
      else if (loop_b[j]) ;
  end
  initial begin
    #7;
    loop_a = 3'b101;
    loop_b = 3'b111;
    #1;
    loop_a = 3'b000;
  end

  // The scope of a report includes generate and named blocks
  logic [1:0] gen_sel = 2'b01;
  if (1) begin : gen_blk
    always_comb begin : named
      priority case (1'b1)
        gen_sel[0]: ;
        gen_sel[1]: ;
      endcase
    end
  end
  initial begin
    #8;
    gen_sel = 2'b00;
    #1;
    gen_sel = 2'b01;
  end

  // Where a report cannot be pending, it is made at the check
  function automatic void check_in_function(logic [1:0] sel);
    unique case (1'b1)
      sel[0]: ;
      sel[1]: ;
    endcase
  endfunction
  initial begin : in_function
    #10;
    check_in_function(2'b11);
    $display("[%0t] in_function: after the check", $time);
  end

  initial begin
    #11;
    fork
      begin : in_join_none
        logic [1:0] sel;
        sel = 2'b11;
        unique case (1'b1)
          sel[0]: ;
          sel[1]: ;
        endcase
        $display("[%0t] in_join_none: after the check", $time);
      end
    join_none
  end

  logic clk = 1'b0;
  bit ok = 1'b0;
  initial begin
    #12;
    clk = 1'b1;
  end
  always @(posedge clk) begin : in_assertion_action
    assert property (ok)
    else begin
      unique case (1'b1)
        clk: ;
        !ok: ;
      endcase
      $display("[%0t] in_assertion_action: after the check", $time);
    end
  end

  final begin : in_final
    logic [1:0] sel;
    sel = 2'b11;
    unique case (1'b1)
      sel[0]: ;
      sel[1]: ;
    endcase
    $display("[%0t] in_final: after the check", $time);
  end

  initial begin
    #20;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
