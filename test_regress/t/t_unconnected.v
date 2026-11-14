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
  wire [2:0] o_p1;
  wire [2:0] o_p0;
  wire signed [2:0] o_p1_signed;
  wire signed [2:0] o_p0_signed;
  wire [32:0] o_p1_wide;
  wire [32:0] o_p0_wide;
  wire [1:0][3:0] o_p1_packed;
  wire [1:0][3:0] o_p0_packed;
  wire [2:0] od_omit;
  wire [2:0] od_empty;
  wire [2:0] od_blank;

  // verilator lint_off PINMISSING
  sub_0 sub_0 (.o_0);
  sub_1 sub_1 (.o_1);
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
  sub_d sub_d_omit (.od(od_omit));
  sub_d sub_d_empty (
      .id(),
      .od(od_empty)
  );
  sub_d sub_d_blank (, od_blank);

  always @(posedge clk) begin
    if (o_0 !== 1'b0) $stop;
    if (o_1 !== 1'b1) $stop;
    //4-state if (o_n !== 1'bz) $stop;
    if (o_p1 !== 3'b111) $stop;
    if (o_p0 !== 3'b000) $stop;
    if (o_p1_signed !== 3'b111) $stop;
    if (o_p0_signed !== 3'b000) $stop;
    if (o_p1_wide !== {33{1'b1}}) $stop;
    if (o_p0_wide !== {33{1'b0}}) $stop;
    if (o_p1_packed !== 8'hff) $stop;
    if (o_p0_packed !== 8'h00) $stop;
    `checkh(od_omit, 3'h2);  // Default value, not pulled
    `checkh(od_empty, 3'h7);  // Explicit empty connection, so no default value
    `checkh(od_blank, 3'h2);  // Default value, not pulled
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule

`unconnected_drive pull0
module sub_0 (
    input i,
    output wire o_0
);
  assign o_0 = i;
endmodule

`unconnected_drive pull1
module sub_1 (
    input i,
    output wire o_1
);
  assign o_1 = i;
endmodule

module sub_d (
    input [2:0] id = 3'h2,
    output wire [2:0] od
);
  assign od = id;
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
