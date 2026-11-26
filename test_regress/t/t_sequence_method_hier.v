// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Sequence methods of sequences declared in modules and interfaces below the top
// (IEEE 1800-2023 16.13.6), each instance with its own end points

interface ifc (
    input clk,
    input logic a,
    input logic b
);
  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_ab;
    @(posedge clk) a ##1 b;
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

  // Same clock: 'matched' sees each end point at the next tick (IEEE 1800-2023 F.6.1)
  int n_matched = 0;
  assert property (@(posedge clk) !s_ab.matched)
  else ++n_matched;

  final begin
    `checkd(n_wait, n_ref);
    `checkd(n_matched, n_ref);
  end
endinterface

module leaf (
    input clk,
    input logic a,
    input logic b
);
  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_ab;
    @(posedge clk) a ##1 b;
  endsequence
  // verilog_format: on

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

  int n_matched = 0;
  assert property (@(posedge clk) !s_ab.matched)
  else ++n_matched;

  final begin
    `checkd(n_wait, n_ref);
    `checkd(n_matched, n_ref);
  end
endmodule

module mid (
    input clk,
    input logic a,
    input logic b,
    input logic c
);
  // Two instances of the same module, with different end points
  leaf u_ab (.clk, .a(a), .b(b));
  leaf u_bc (.clk, .a(b), .b(c));
  ifc u_ifc (.clk, .a(c), .b(a));

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_ca;
    @(posedge clk) c ##1 a;
  endsequence
  // verilog_format: on

  int n_ref = 0;
  bit prev_c = 0;
  always @(posedge clk) begin
    if (prev_c && a) ++n_ref;
    prev_c = c;
  end

  int n_wait = 0;
  initial forever begin
    wait (s_ca.triggered);
    ++n_wait;
    @(posedge clk);
  end

  int n_matched = 0;
  assert property (@(posedge clk) !s_ca.matched)
  else ++n_matched;

  final begin
    `checkd(n_wait, n_ref);
    `checkd(n_matched, n_ref);
  end
endmodule

module t (
    input clk
);
  localparam int NCYC = 60;
  int unsigned crc = 32'h1;
  logic a = 0, b = 0, c = 0;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    // Quiet tail so no end point is on the final tick
    a <= cyc < NCYC - 5 && crc[0];
    b <= cyc < NCYC - 5 && crc[5];
    c <= cyc < NCYC - 5 && crc[9];
    if (cyc == NCYC) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  mid u_mid (.clk, .a, .b, .c);

  final begin
    // Each instance saw end points, and the two instances of leaf different ones
    `checkd(u_mid.u_ab.n_ref > 0 && u_mid.u_bc.n_ref > 0 && u_mid.u_ifc.n_ref > 0, 1'b1);
    `checkd(u_mid.n_ref > 0, 1'b1);
    `checkd(u_mid.u_ab.n_ref != u_mid.u_bc.n_ref, 1'b1);
  end
endmodule
