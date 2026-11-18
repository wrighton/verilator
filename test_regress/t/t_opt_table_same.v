// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2021 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int i;
  int j;

  reg [2:0] cyc;

  initial cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  always @* begin
    case (cyc)
      3'b000: i = 0;
      3'b001: i = 1;
      3'b010: i = 2;
      3'b100: i = 4;
      3'b101: i = 5;
      default: i = 99;
    endcase
  end

  // Equivalent to above
  always @* begin
    case (cyc)
      3'b101: j = 5;
      3'b100: j = 4;
      3'b010: j = 2;
      3'b001: j = 1;
      3'b000: j = 0;
      default: j = 99;
    endcase
  end

  // Expected sub outputs by input value
  localparam logic [6:0] EXP_O[8] = '{10, 21, 32, 99, 43, 54, 99, 99};
  localparam logic [6:0] EXP_O2[8] = '{0, 0, 3, 0, 0, 5, 0, 0};

  // Same logic in different instances, reading different inputs
  logic [2:0] sel1;
  assign sel1 = cyc + 3'd3;
  logic [6:0] a0, a1, b0, b1;
  sub u0 (.clk, .sel(cyc), .o(a0), .o2(b0));
  sub u1 (.clk, .sel(sel1), .o(a1), .o2(b1));
  logic [6:0] b0_exp = 0;
  logic [6:0] b1_exp = 0;
  always @(posedge clk) begin
    if (cyc != 0) begin
      `checkd(a0, EXP_O[cyc-3'd1]);
      `checkd(a1, EXP_O[cyc+3'd2]);
    end
    `checkd(b0, b0_exp);
    `checkd(b1, b1_exp);
    if (EXP_O2[cyc] != 0) b0_exp <= EXP_O2[cyc];
    if (EXP_O2[sel1] != 0) b1_exp <= EXP_O2[sel1];
  end

  // Same logic other than a constant
  logic [6:0] c0, c3;
  sub_const #(.K(0)) uc0 (.clk, .sel(cyc), .o(c0));
  sub_const #(.K(3)) uc3 (.clk, .sel(cyc), .o(c3));
  always @(posedge clk) begin
    if (cyc != 0) begin
      `checkd(c0, EXP_O[cyc-3'd1]);
      `checkd(c3, EXP_O[(cyc-3'd1)^3'd3]);
    end
  end

  // Same logic with jumps to corresponding blocks, or to other blocks
  logic [6:0] e0, e1, e2, f0, f1, f2;
  sub_jump #(.OUTER(0)) uj0 (.clk, .sel(cyc), .o(e0), .o2(f0));
  sub_jump #(.OUTER(0)) uj1 (.clk, .sel(sel1), .o(e1), .o2(f1));
  sub_jump #(.OUTER(1)) uj2 (.clk, .sel(cyc), .o(e2), .o2(f2));
  logic [6:0] e0_exp = 0;
  logic [6:0] e1_exp = 0;
  logic [6:0] e2_exp = 0;
  logic [6:0] f0_exp = 0;
  logic [6:0] f1_exp = 0;
  logic [6:0] f2_exp = 0;
  always @(posedge clk) begin
    `checkd(e0, e0_exp);
    `checkd(e1, e1_exp);
    `checkd(e2, e2_exp);
    `checkd(f0, f0_exp);
    `checkd(f1, f1_exp);
    `checkd(f2, f2_exp);
    if (cyc[1:0] == 0) e0_exp <= EXP_O[cyc];
    if (sel1[1:0] == 0) e1_exp <= EXP_O[sel1];
    if (cyc[1:0] == 0) e2_exp <= EXP_O[cyc];
    if (cyc[0] || !cyc[1]) f0_exp <= 7'(cyc) + 7'd20;
    if (sel1[0] || !sel1[1]) f1_exp <= 7'(sel1) + 7'd20;
    if (!cyc[0]) f2_exp <= 7'(cyc) + 7'd20;
  end

  always @(posedge clk) begin
    $display("cyle %d = %d %d", cyc, i, j);
    if (cyc == 7) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module sub (
    input clk,
    input [2:0] sel,
    output logic [6:0] o,
    output logic [6:0] o2
);
  initial o2 = 0;
  always @(posedge clk) begin
    case (sel)
      3'b000: o <= 10;
      3'b001: o <= 21;
      3'b010: begin
        o <= 32;
        o2 <= 3;
      end
      3'b100: o <= 43;
      3'b101: begin
        o <= 54;
        o2 <= 5;
      end
      default: o <= 99;
    endcase
  end
endmodule

module sub_const #(
    parameter logic [2:0] K = 0
) (
    input clk,
    input [2:0] sel,
    output logic [6:0] o
);
  const logic [2:0] KC = K;
  always @(posedge clk) begin
    case (sel ^ KC)
      3'b000: o <= 10;
      3'b001: o <= 21;
      3'b010: o <= 32;
      3'b100: o <= 43;
      3'b101: o <= 54;
      default: o <= 99;
    endcase
  end
endmodule

module sub_jump #(
    parameter bit OUTER = 0
) (
    input clk,
    input [2:0] sel,
    output logic [6:0] o,
    output logic [6:0] o2
);
  initial o = 0;
  initial o2 = 0;
  always @(posedge clk) begin : outer
    begin : inner
      if (sel[0]) begin
        if (OUTER) disable outer;
        else disable inner;
      end
      if (sel[1]) begin
        if (OUTER) disable inner;
        else disable outer;
      end
      case (sel)
        3'b000: o <= 10;
        3'b010: o <= 32;
        3'b100: o <= 43;
        default: o <= 99;
      endcase
    end
    o2 <= 7'(sel) + 7'd20;
  end
endmodule
