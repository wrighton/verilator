// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Streams of unpacked parameters in constant expressions
module sub #(
    parameter logic [3:0] Q[2] = '{4'h1, 4'h2}
);
  localparam logic [7:0] QB = {>>{Q}};
endmodule

module t;
  typedef struct {
    logic [3:0] a;
    logic [7:0] b;
  } s_t;

  localparam logic [3:0] PD[1:0] = '{4'ha, 4'h5};
  localparam logic [3:0] PA[0:1] = '{4'ha, 4'h5};
  localparam logic [3:0] PN[2:1] = '{4'hc, 4'h3};
  localparam logic [3:0] P2[2][2] = '{'{4'h1, 4'h2}, '{4'h3, 4'h4}};
  localparam s_t S = '{4'h7, 8'h9e};
  localparam logic [7:0] C[2] = '{8'h42, 8'h43};

  localparam logic [7:0] BD = {>>{PD}};
  localparam logic [7:0] BL = {<<4{PD}};
  localparam logic [7:0] BA = {>>{PA}};
  localparam logic [7:0] BN = {>>{PN}};
  localparam logic [15:0] B2 = {>>{P2}};
  localparam logic [11:0] BS = {>>{S}};
  localparam logic [11:0] BM = {>>{4'hf, PD}};
  localparam string STR = {>>{C}};
  // A bit-stream cast is folded the same way
  typedef logic [7:0] b8_t;
  localparam b8_t BC = b8_t'(PD);

  sub u1 ();
  sub #(.Q('{4'h6, 4'h9})) u2 ();

  logic [BD[3:0]:0] sized;

  if (BD == 8'ha5) begin : g_ok
    localparam int OK = 1;
  end
  if (b8_t'(PA) == 8'ha5) begin : g_cast
    localparam int OK = 1;
  end

  initial begin
    `checkh(BD, 8'ha5);
    `checkh(BL, 8'h5a);
    `checkh(BA, 8'ha5);
    `checkh(BN, 8'hc3);
    `checkh(B2, 16'h1234);
    `checkh(BS, 12'h79e);
    `checkh(BM, 12'hfa5);
    `checks(STR, "BC");
    `checkh(BC, 8'ha5);
    `checkh(u1.QB, 8'h12);
    `checkh(u2.QB, 8'h69);
    `checkh($bits(sized), 6);
    `checkh(g_ok.OK, 1);
    `checkh(g_cast.OK, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
