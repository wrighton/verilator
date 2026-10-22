// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Sequence method 'triggered' (IEEE 1800-2023 16.13.6)

// Other things named 'triggered'
class Holder;
  bit triggered = 1'b1;
endclass

module sub;
  bit triggered = 1'b1;
endmodule

module t (
  input clk
);
  localparam int NCYC = 40;
  int unsigned crc = 32'h1;
  logic a = 0, b = 0;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    // Quiet tail so no end point is on the final tick
    a <= cyc < NCYC - 5 && crc[0];
    b <= cyc < NCYC - 5 && crc[5];
    if (cyc == NCYC) $finish;
  end

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_ab;
    @(posedge clk) a ##1 b;
  endsequence
  sequence s_xy(x, y);
    @(posedge clk) x ##1 y;
  endsequence
  // verilog_format: on

  // Reference: ticks on which 'a ##1 b' ends
  int n_ref = 0;
  bit prev_a = 0;
  always @(posedge clk) begin
    if (prev_a && b) ++n_ref;
    prev_a = a;
  end

  int n_wait = 0;
  initial forever begin
    wait (s_ab.triggered);
    ++n_wait;
    @(posedge clk);
  end

  // A second use of the same sequence
  int n_wait2 = 0;
  initial forever begin
    wait (s_ab.triggered);
    ++n_wait2;
    @(posedge clk);
  end

  // A sequence instance with arguments
  int n_args = 0;
  initial forever begin
    wait (s_xy(a, b).triggered);
    ++n_args;
    @(posedge clk);
  end

  // Only true in the time step of the end point
  int n_later = 0;
  always @(negedge clk) if (s_ab.triggered) ++n_later;

  function automatic Holder new_holder();
    Holder h = new;
    return h;
  endfunction
  sub u_sub ();
  Holder holder = new;
  initial begin
    @(posedge clk);
    `checkd(new_holder().triggered, 1'b1);
    `checkd(holder.triggered, 1'b1);
    `checkd(u_sub.triggered, 1'b1);
  end

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(n_wait, n_ref);
    `checkd(n_wait2, n_ref);
    `checkd(n_args, n_ref);
    `checkd(n_later, 0);
    `checkd(n_ref, 8);
    $write("*-* All Finished *-*\n");
  end
endmodule
