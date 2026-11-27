// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A process forked by a procedure starts in the region the procedure runs in, so before the
// NBA updates of its time step (IEEE 1800-2023 9.3.2, 4.4.2.2)
module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // Test: a process forked at a clock edge reads the values before the edge's NBA updates
  int q = 0;
  always @(posedge clk) q <= q + 1;
  wire [31:0] q2 = q * 2;
  int q_seen = -1, q2_seen = -1;
  always @(posedge clk)
    fork
      begin
        q_seen = q;
        q2_seen = q2;
      end
    join_none

  // Test: logic reading what it writes settles in the time step
  int fw = 0;
  wire [31:0] fw2 = fw + 1;
  always @(posedge clk)
    fork
      fw = q;
    join_none

  // Test: so does one forked at the edge of a clock that a delay makes
  logic dclk = 0;
  always #5 dclk = ~dclk;
  int dq = 0, dq_seen = -1;
  always @(posedge dclk) dq <= dq + 1;
  always @(posedge dclk)
    fork
      dq_seen = dq;
    join_none
  always @(negedge dclk) if (dq > 0) `checkd(dq_seen, dq - 1);

  // Test: one waiting a delay first runs the same
  int late_seen = -1;
  always @(posedge clk)
    fork
      #1 late_seen = q;
    join_none

  // Test: a procedure forking processes sees an edge of its clock at time 0
  logic zclk = 0;
  initial zclk = 1;
  int zclk_n = 0, zclk_child_n = 0;
  always @(posedge zclk) begin
    ++zclk_n;
    fork
      ++zclk_child_n;
    join_none
  end
  initial begin
    #1;
    `checkd(zclk_n, 1);
    `checkd(zclk_child_n, 1);
  end

  // Test: so does one forked by a procedure waiting at its clock edge
  int wait_seen = -1;
  always begin
    @(posedge clk);
    fork
      wait_seen = q;
    join_none
  end

  // Test: other clocked procedures read a blocking write of the forking procedure as before
  int x = 0, y = 0, z = 0, w = 0, dummy;
  always @(posedge clk) begin
    x = x + 1;
    w = z;
    fork
      dummy = 1;
    join_none
  end
  always @(posedge clk) y = x;
  always @(posedge clk) z = z + 1;

  // Test: not yet a process forked by a combinational procedure, which starts after the NBA
  // updates
  logic go = 0;
  always @(posedge clk) go = !go;
  int comb_seen = -1;
  always @* begin
    comb_seen = go ? -2 : -3;
    fork
      comb_seen = q;
    join_none
  end
  // Test: one forked in a task the procedure calls starts before them
  int task_seen = -1;
  task automatic forkRead();
    fork
      task_seen = q;
    join_none
  endtask
  always @(posedge clk) forkRead();

  always @(negedge clk) begin
    if (cyc > 0) begin
      `checkd(q_seen, q - 1);
      `checkd(q2_seen, (q - 1) * 2);
      `checkd(wait_seen, q - 1);
      `checkd(fw, q - 1);
      `checkd(fw2, q);
      `checkd(late_seen, q);
      `checkd(comb_seen, q);
      `checkd(task_seen, q - 1);
      `checkd(x, cyc);
    end
    if (cyc == 3) begin
      `checkd(y, 2);
      `checkd(w, 3);
    end
    if (cyc == 6) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
