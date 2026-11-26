// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module sub;
  int n = 0;
  function automatic void report();
    ++n;
  endfunction
  logic x = 1'b1;
  always @(x) begin : victim
    assert #0 (x)
    else report();
  end
endmodule

// A disable of a deferred assertion cancels its pending reports, and a disable of the outermost
// scope of a procedure flushes the pending reports of its process, also from another process
// and when the procedure is not running. A disable of another scope keeps them, and a report
// made after a disable, or matured before it, is made (IEEE 1800-2023 16.4.4).
module t;
  // IEEE 1800-2023 16.4.4 example: a disable of a deferred assertion in its own process
  logic bad_val = 1'b1, bad_val_ok = 1'b0;
  int n_a1 = 0;
  function automatic void report_a1();
    ++n_a1;
  endfunction
  always @(bad_val or bad_val_ok) begin : b1
    a1 : assert #0 (bad_val)
    else report_a1();
    if (bad_val_ok) begin
      disable a1;
    end
  end
  initial begin
    #1;
    bad_val = 1'b0;
    bad_val_ok = 1'b1;
    #1;
    `checkd(n_a1, 0);
    // Not disabled
    bad_val_ok = 1'b0;
    #1;
    `checkd(n_a1, 1);
    // A later disable keeps a matured report
    bad_val_ok = 1'b1;
    #1;
    `checkd(n_a1, 1);
  end

  // IEEE 1800-2023 16.4.4 example: a disable of the outermost scope of another procedure
  logic a = 1'b1, b = 1'b1, clear_b2 = 1'b0;
  logic [7:0] c = 8'h0;
  int n_a3 = 0;
  function automatic void report_a3();
    ++n_a3;
  endfunction
  always @(a or b or c) begin : b2
    if (c == 8'hff) begin
      a2 : assert #0 (a && b);
    end
    else begin
      a3 : assert #0 (a || b)
      else report_a3();
    end
  end
  always @(clear_b2) begin : b3
    disable b2;
  end
  initial begin
    #1;
    a = 1'b0;
    b = 1'b0;
    clear_b2 <= 1'b1;
    #1;
    `checkd(n_a3, 0);
  end

  // A report made after a disable in the same time step is made
  int n_a4 = 0;
  function automatic void report_a4();
    ++n_a4;
  endfunction
  initial begin
    #1;
    for (int i = 0; i < 2; ++i) begin
      a4 : assert #0 (0)
      else report_a4();
      if (i == 0) disable a4;
    end
    #1;
    `checkd(n_a4, 1);
  end

  // A disable of a scope that is not the outermost one keeps the pending report
  logic i_val = 1'b1, i_go = 1'b0;
  int n_a5 = 0;
  int i_runs = 0;
  function automatic void report_a5();
    ++n_a5;
  endfunction
  always @(i_val) begin : b5
    begin : inner
      a5 : assert #0 (i_val)
      else report_a5();
      ++i_runs;
    end
  end
  always @(i_go) begin : b6
    disable b5.inner;
  end
  initial begin
    #1;
    i_val = 1'b0;
    i_go <= 1'b1;
    #1;
    `checkd(n_a5, 1);
  end

  // A disable of a named block holding only a deferred assertion keeps the pending report: the
  // block is a scope that is not the outermost one, unlike a statement label
  logic q_val = 1'b1, q_go = 1'b0;
  int n_q2 = 0, n_q3 = 0;
  function automatic void report_q2();
    ++n_q2;
  endfunction
  function automatic void report_q3();
    ++n_q3;
  endfunction
  always @(q_val) begin : p2
    begin : blk
      assert #0 (q_val)
      else report_q2();
    end
  end
  always @(q_val) begin : p3
    begin : mid
      begin : deep
        assert #0 (q_val)
        else report_q3();
      end
    end
  end
  always @(q_go) begin : q_kill
    disable p2.blk;
    disable p3.mid.deep;
  end
  initial begin
    #1;
    q_val = 1'b0;
    q_go <= 1'b1;
    #1;
    `checkd(n_q2, 1);
    `checkd(n_q3, 1);
  end

  // A disable by a hierarchical name of the outermost scope of a procedure in another instance
  sub u_sub ();
  logic h_go = 1'b0, h_go2 = 1'b0;
  always @(h_go) begin : b7
    disable u_sub.victim;
  end
  always @(h_go2) begin : b8
    disable u_sub.victim;
  end
  initial begin
    #1;
    u_sub.x = 1'b0;
    h_go <= 1'b1;
    #1;
    `checkd(u_sub.n, 0);
    u_sub.x = 1'b1;
    #1;
    u_sub.x = 1'b0;
    h_go2 <= 1'b1;
    #1;
    `checkd(u_sub.n, 0);
  end

  initial begin
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
