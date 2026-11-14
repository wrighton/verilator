// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  wire o_n;
  wire o_0;
  wire o_1;
<<<<<<< 9b3b1d9852475b546e24eb617c8869095e66dbb3
  wire [2:0] o_p1;
  wire [2:0] o_p0;
  wire signed [2:0] o_p1_signed;
  wire signed [2:0] o_p0_signed;
  wire [32:0] o_p1_wide;
  wire [32:0] o_p0_wide;
  wire [1:0][3:0] o_p1_packed;
  wire [1:0][3:0] o_p0_packed;
=======
  wire [6:0] ov_0;
  wire [6:0] ov_1;
  wire [4:0] oa_0;
  wire [4:0] oa_1;
  wire [4:0] ot_1;
  wire [3:0] ota_1;
  wire [2:0] osa_1;
  wire osb_1;
  wire osra_1;
  wire [2:0] ovar_1;
  real or_1;
>>>>>>> 07d6b7a970fe2c3db63a78b6ce8adbd2834840cb

  // verilator lint_off PINMISSING
  sub_0 sub_0 (.o_0, .ov_0, .oa_0);
  sub_1 sub_1 (.o_1, .ov_1, .oa_1, .ot_1, .ota_1, .osa_1, .osb_1, .osra_1, .ovar_1, .or_1);
  sub_n sub_n (.o_n);
  sub_p1 sub_p1 (.o(o_p1));
  sub_p0 sub_p0 (.o(o_p0));
  sub_p1_signed sub_p1_signed (.o(o_p1_signed));
  sub_p0_signed sub_p0_signed (.o(o_p0_signed));
  sub_p1_wide sub_p1_wide (.o(o_p1_wide));
  sub_p0_wide sub_p0_wide (.o(o_p0_wide));
  sub_p1_packed sub_p1_packed (.o(o_p1_packed));
  sub_p0_packed sub_p0_packed (.o(o_p0_packed));
  // verilator lint_on PINMISSING

  always @(posedge clk) begin
    if (o_0 !== 1'b0) $stop;
    if (o_1 !== 1'b1) $stop;
    `checkh(ov_0, 7'h0);
    `checkh(ov_1, 7'h7f);
    `checkh(oa_0, 5'h0);
    `checkh(oa_1, 5'h1f);
    `checkh(ot_1, 5'h1f);
    `checkh(ota_1, 4'hf);
    `checkh(osa_1, 3'h7);
    `checkh(osb_1, 1'b1);
    `checkh(osra_1, 1'b0);  // 4-state would be x, not pulled
    `checkh(ovar_1, 3'h7);
    if (or_1 != 0.0) `stop;
    //4-state if (o_n !== 1'bz) $stop;
    if (o_p1 !== 3'b111) $stop;
    if (o_p0 !== 3'b000) $stop;
    if (o_p1_signed !== 3'b111) $stop;
    if (o_p0_signed !== 3'b000) $stop;
    if (o_p1_wide !== {33{1'b1}}) $stop;
    if (o_p0_wide !== {33{1'b0}}) $stop;
    if (o_p1_packed !== 8'hff) $stop;
    if (o_p0_packed !== 8'h00) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule

`unconnected_drive pull0
module sub_0 (
    input i,
    input [6:0] iv,
    input [4:0] ia[2],
    output wire o_0,
    output wire [6:0] ov_0,
    output wire [4:0] oa_0
);
  assign o_0 = i;
  assign ov_0 = iv;
  assign oa_0 = ia[1];
endmodule

typedef logic [4:0] t5_t;
typedef logic [3:0] tarr_t[2];
typedef struct {
  logic [2:0] a;
  logic b;
} ustruct_t;
typedef struct {
  logic a;
  real r;
} ustructr_t;

`unconnected_drive pull1
module sub_1 (
    input i,
    input [6:0] iv,
    input [4:0] ia[2],
    input t5_t it,
    input tarr_t ita,
    input ustruct_t is,
    input var ustructr_t isr,  // Not all integral bits, so no pull value
    input var logic [2:0] ivar,  // Has a pull value, so pulled, also as a variable
    input var real ir,  // No pull value, so not pulled
    output wire o_1,
    output wire [6:0] ov_1,
    output wire [4:0] oa_1,
    output wire [4:0] ot_1,
    output wire [3:0] ota_1,
    output wire [2:0] osa_1,
    output wire osb_1,
    output wire osra_1,
    output wire [2:0] ovar_1,
    output real or_1
);
  assign o_1 = i;
  assign ov_1 = iv;
  assign oa_1 = ia[1];
  assign ot_1 = it;
  assign ota_1 = ita[0];
  assign osa_1 = is.a;
  assign osb_1 = is.b;
  assign osra_1 = isr.a;
  assign ovar_1 = ivar;
  assign or_1 = ir;
endmodule

`nounconnected_drive
module sub_n (
    input i,
    output wire o_n
);
  assign o_n = i;
endmodule

`unconnected_drive pull1
module sub_p1 (
    input [2:0] i,
    output wire [2:0] o
);
  assign o = i;
endmodule

module sub_p1_signed (
    input signed [2:0] i,
    output wire signed [2:0] o
);
  assign o = i;
endmodule

module sub_p1_wide (
    input [32:0] i,
    output wire [32:0] o
);
  assign o = i;
endmodule

module sub_p1_packed (
    input [1:0][3:0] i,
    output wire [1:0][3:0] o
);
  assign o = i;
endmodule

`unconnected_drive pull0
module sub_p0 (
    input [2:0] i,
    output wire [2:0] o
);
  assign o = i;
endmodule

module sub_p0_signed (
    input signed [2:0] i,
    output wire signed [2:0] o
);
  assign o = i;
endmodule

module sub_p0_wide (
    input [32:0] i,
    output wire [32:0] o
);
  assign o = i;
endmodule

module sub_p0_packed (
    input [1:0][3:0] i,
    output wire [1:0][3:0] o
);
  assign o = i;
endmodule

`nounconnected_drive
