// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Sequence methods in generate blocks (IEEE 1800-2023 16.13.6, 27.5), each generate loop
// iteration with its own end points

module t (
    input clk
);
  localparam int NCYC = 60;
  int unsigned crc = 32'h1;
  logic [3:0] a = 0;
  logic b = 0;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    // Quiet tail so no end point is on the final tick
    a <= cyc < NCYC - 5 ? crc[3:0] : 4'b0;
    b <= cyc < NCYC - 5 && crc[7];
    if (cyc == NCYC) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_xy(x, y);
    @(posedge clk) x ##1 y;
  endsequence
  // verilog_format: on

  for (genvar i = 0; i < 3; ++i) begin : g_loop
    // Reference: ticks on which 'a[i] ##1 b' ends
    int n_ref = 0;
    bit prev = 0;
    always @(posedge clk) begin
      if (prev && b) ++n_ref;
      prev = a[i];
    end

    // verilog_format: off  // verible does not support clocking events inside sequence declarations
    sequence s_loc;
      @(posedge clk) a[i] ##1 b;
    endsequence
    // verilog_format: on

    // Sequence of the generate block
    int n_loc = 0;
    initial
      forever begin
        wait (s_loc.triggered);
        ++n_loc;
        @(posedge clk);
      end

    // Module sequence with a genvar in an actual
    int n_genvar = 0;
    initial
      forever begin
        wait (s_xy(a[i], b).triggered);
        ++n_genvar;
        @(posedge clk);
      end

    // Module sequence with a variable of the generate block as an actual
    logic v;
    assign v = a[i];
    int n_var = 0;
    initial
      forever begin
        wait (s_xy(v, b).triggered);
        ++n_var;
        @(posedge clk);
      end

    // Same clock: 'matched' sees each end point at the next tick (IEEE 1800-2023 F.6.1)
    int n_matched = 0;
    assert property (@(posedge clk) !s_loc.matched)
    else ++n_matched;

    final begin
      `checkd(n_loc, n_ref);
      `checkd(n_genvar, n_ref);
      `checkd(n_var, n_ref);
      `checkd(n_matched, n_ref);
    end
  end

  if (NCYC > 0) begin : g_if
    int n_ref = 0;
    bit prev = 0;
    always @(posedge clk) begin
      if (prev && b) ++n_ref;
      prev = a[3];
    end

    // verilog_format: off  // verible does not support clocking events inside sequence declarations
    sequence s_if;
      @(posedge clk) a[3] ##1 b;
    endsequence
    // verilog_format: on

    int n_if = 0;
    initial
      forever begin
        wait (s_if.triggered);
        ++n_if;
        @(posedge clk);
      end

    final `checkd(n_if, n_ref);
  end

  final begin
    // The iterations saw end points, different ones
    `checkd(g_loop[0].n_ref > 0 && g_loop[1].n_ref > 0 && g_loop[2].n_ref > 0, 1'b1);
    `checkd(g_loop[0].n_ref != g_loop[1].n_ref || g_loop[1].n_ref != g_loop[2].n_ref, 1'b1);
    `checkd(g_if.n_ref > 0, 1'b1);
  end
endmodule
