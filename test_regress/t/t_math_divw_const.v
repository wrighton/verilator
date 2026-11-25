// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Constant and run-time division agree with the expected quotient and remainder
module sub #(
    parameter int W = 1,
    parameter logic [W-1:0] A = '0,
    parameter logic [W-1:0] B = '0,
    parameter logic [W-1:0] Q = '0,
    parameter logic [W-1:0] R = '0
) (
    input clk,
    input int cyc
);
  localparam logic [W-1:0] FoldedQ = A / B;
  localparam logic [W-1:0] FoldedR = A % B;
  logic [W-1:0] a;
  logic [W-1:0] b;
  always @(posedge clk) begin
    if (cyc == 0) begin
      `checkh(FoldedQ, Q);
      `checkh(FoldedR, R);
      a <= A;
      b <= B;
    end else if (cyc == 1) begin
      `checkh(a / b, Q);
      `checkh(a % b, R);
    end
  end
endmodule

module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 2) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Divisors whose most significant set bit is the top bit of a 32-bit word
  sub #(
      .W(65),
      .A(65'h1_2345_6789_abcd_ef01),
      .B(65'h0_8000_0000_0000_0001),
      .Q(65'h2),
      .R(65'h0_2345_6789_abcd_eeff)
  ) u_65a (
      .*
  );
  sub #(
      .W(65),
      .A(65'h1_ffff_ffff_ffff_ffff),
      .B(65'h0_8000_0000_0000_0000),
      .Q(65'h3),
      .R(65'h0_7fff_ffff_ffff_ffff)
  ) u_65b (
      .*
  );
  sub #(
      .W(96),
      .A(96'h1234_5678_9abc_def0_1234_5678),
      .B(96'h0000_0000_8000_0000_0000_0001),
      .Q(96'h2468_acf1),
      .R(96'h0000_0000_1abc_deef_edcb_a987)
  ) u_96a (
      .*
  );
  sub #(
      .W(96),
      .A(96'hffff_ffff_ffff_ffff_ffff_ffff),
      .B(96'h8000_0000_0000_0000_0000_0003),
      .Q(96'h1),
      .R(96'h7fff_ffff_ffff_ffff_ffff_fffc)
  ) u_96b (
      .*
  );
  sub #(
      .W(128),
      .A(128'h0123_4567_89ab_cdef_fedc_ba98_7654_3210),
      .B(128'h0000_0000_ffff_ffff_0000_0000_0000_0001),
      .Q(128'h0123_4567),
      .R(128'h0000_0000_8acf_1356_fedc_ba98_7530_eca9)
  ) u_128a (
      .*
  );
  sub #(
      .W(128),
      .A(128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff),
      .B(128'h8000_0000_0000_0000_0000_0000_0000_0001),
      .Q(128'h1),
      .R(128'h7fff_ffff_ffff_ffff_ffff_ffff_ffff_fffe)
  ) u_128b (
      .*
  );

endmodule
