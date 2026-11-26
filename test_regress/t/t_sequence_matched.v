// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Sequence method 'matched' (IEEE 1800-2023 16.13.5, 16.13.6) holds at a tick of the clock it
// is read on when its sequence reached an end point in a time step after the previous tick of
// that clock, and before the current one (IEEE 1800-2023 F.6.1)

module t;
  localparam int NCYC = 120;
  logic clk_a = 0, clk_b = 0, clk_c = 0;
  always #5 clk_a = ~clk_a;  // Posedges at 5, 15, 25, ...
  initial begin  // Posedges at 15, 35, 55, ..., with those of clk_a
    #5;
    forever #10 clk_b = ~clk_b;
  end
  always #7 clk_c = ~clk_c;  // Posedges at 7, 21, 35, ...

  int unsigned crc = 32'h1;
  logic a = 0, b = 0, c = 0, d = 0;
  int cyc = 0;
  always @(negedge clk_a) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[5];
    c <= crc[9];
    d <= crc[13];
    if (cyc == NCYC) $finish;
  end

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_ab;
    @(posedge clk_a) a ##1 b;
  endsequence
  sequence s_xy(x, y);
    @(posedge clk_a) x ##1 y;
  endsequence
  // As sequence e3 in IEEE 1800-2023 16.13.6
  sequence s_dest;
    @(posedge clk_b) c ##1 s_ab.matched ##1 d;
  endsequence
  // verilog_format: on

  // Reference: count of end points of 'a ##1 b', updated after the time step's reads
  int n_end = 0;
  bit prev_a = 0;
  always @(posedge clk_a) begin
    if (prev_a && b) n_end <= n_end + 1;
    prev_a = a;
  end

  // Same clock: an end point is seen at the next tick
  time ref_a[$], got_a[$];
  int seen_a = 0;
  always @(posedge clk_a) begin
    if (n_end != seen_a) ref_a.push_back($time);
    seen_a = n_end;
  end
  assert property (@(posedge clk_a) !s_ab.matched)
  else got_a.push_back($time);

  // Slower clock, ticking with clk_a every other tick
  time ref_b[$], got_b[$];
  int seen_b = 0;
  bit [1:0] hist_b = 0;  // Reference 'matched' at the two previous ticks
  bit [1:0] hist_c = 0;  // c at the two previous ticks
  int n_dest_ref = 0;
  always @(posedge clk_b) begin
    if (hist_c[1] && hist_b[0] && d) ++n_dest_ref;
    hist_b = {hist_b[0], n_end != seen_b};
    hist_c = {hist_c[0], c};
    if (n_end != seen_b) ref_b.push_back($time);
    seen_b = n_end;
  end
  assert property (@(posedge clk_b) !s_ab.matched)
  else got_b.push_back($time);

  int n_dest = 0;
  cover property (s_dest) ++n_dest;

  // Unrelated clock, with an instance with arguments
  time ref_c[$], got_c[$];
  int seen_c = 0;
  always @(posedge clk_c) begin
    if (n_end != seen_c) ref_c.push_back($time);
    seen_c = n_end;
  end
  property p_c;
    @(posedge clk_c) !s_xy(a, b).matched;
  endproperty
  assert property (p_c)
  else got_c.push_back($time);

  final begin
    `checkd(got_a.size(), ref_a.size());
    foreach (ref_a[i]) `checkd(got_a[i], ref_a[i]);
    `checkd(got_b.size(), ref_b.size());
    foreach (ref_b[i]) `checkd(got_b[i], ref_b[i]);
    `checkd(got_c.size(), ref_c.size());
    foreach (ref_c[i]) `checkd(got_c[i], ref_c[i]);
    `checkd(n_dest, n_dest_ref);
    `checkd(ref_a.size() > 10, 1);
    `checkd(ref_b.size() > 5, 1);
    `checkd(ref_c.size() > 5, 1);
    `checkd(n_dest > 0, 1);
    $write("*-* All Finished *-*\n");
  end
endmodule
