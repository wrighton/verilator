// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// Upwards references to parameters of a module specialized several ways

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  int cyc = 0;
  // Test: references by module name, from a module shared by two specializations
  mid #(.SCALE(3)) m3 ();
  mid #(.SCALE(5)) m5 ();
  always @(posedge clk) if (cyc == 1) begin
    `checkd(m3.l.scale, 3);
    `checkd(m5.l.scale, 5);
    `checkd(m3.l.local_scale, 30);
    `checkd(m5.l.local_scale, 50);
    `checkd(m3.l.arr_scale, 4);
    `checkd(m5.l.arr_scale, 6);
    `checkd(m3.l.wire_scale, 3);
    `checkd(m5.l.wire_scale, 5);
  end

  // Test: reference by instance name
  wrap #(.SCALE(3)) w3 ();
  wrap #(.SCALE(5)) w5 ();
  always @(posedge clk) if (cyc == 1) begin
    `checkd(w3.r.scale, 3);
    `checkd(w5.r.scale, 5);
  end

  // Test: specializations from a generate loop
  for (genvar i = 1; i <= 3; ++i) begin : g
    mid #(.SCALE(i)) m ();
  end
  always @(posedge clk) if (cyc == 1) begin
    `checkd(g[1].m.l.scale, 1);
    `checkd(g[2].m.l.scale, 2);
    `checkd(g[3].m.l.scale, 3);
    `checkd(g[1].m.l.local_scale, 10);
    `checkd(g[3].m.l.local_scale, 30);
  end

  // Test: an enum declared in the specialized module, so a different type in each instance
  typed #(.SEL(1)) t1 ();
  typed #(.SEL(2)) t2 ();
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(t1.r.enum_val, 1);
      `checkd(t2.r.enum_val, 2);
      `checks(t1.r.enum_name, "B");
      `checks(t2.r.enum_name, "C");
    end
  end

  // Test: equal values of a different width in each instance, read through a widening cast
  widths #(.SEL(1), .UNTYPED(8'd3), .NEGATIVE(-8'sd3)) cw8 ();
  widths #(.SEL(2), .UNTYPED(16'd3), .NEGATIVE(-16'sd3)) cw16 ();
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(cw8.r.cast_val, 3);
      `checkd(cw16.r.cast_val, 3);
      `checkd(cw8.r.size_cast_val, 3);
      `checkd(cw16.r.size_cast_val, 3);
      `checkd(cw8.r.signed_val, -3);
      `checkd(cw16.r.signed_val, -3);
      `checkd(cw8.r.signed_product, -6);
      `checkd(cw16.r.signed_product, -6);
      `checkd(cw8.r.unsigned_add, 4);
      `checkd(cw16.r.unsigned_add, 4);
    end
  end

  // Test: a checker bound into a specialized module
  fsm #(.W(1)) f1 ();
  fsm #(.W(2)) f2 ();
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(f1.chk.start, 1);
      `checkd(f2.chk.start, 1);
      `checkd(f1.chk.width, 1);
      `checkd(f2.chk.width, 2);
    end
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 2) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module mid #(
    parameter int SCALE = 1
);
  localparam int LOCAL = SCALE * 10;
  localparam int ARR[2] = '{SCALE, SCALE + 1};
  int wire_val;
  assign wire_val = SCALE;
  by_module l ();
endmodule

module by_module;
  int scale;
  int local_scale;
  int arr_scale;
  int wire_scale;
  initial begin
    scale = mid.SCALE;
    local_scale = mid.LOCAL;
    arr_scale = mid.ARR[1];
  end
  assign wire_scale = mid.wire_val;
endmodule

module wrap #(
    parameter int SCALE = 1
);
  mid #(.SCALE(SCALE)) u ();
  by_instance r ();
endmodule

module by_instance;
  int scale;
  initial scale = u.SCALE;
endmodule

module typed #(
    parameter int SEL = 0
);
  typedef enum int {
    A,
    B,
    C
  } enum_t;
  localparam enum_t ENUMED = enum_t'(SEL);
  typed_reader r ();
endmodule

module typed_reader;
  int enum_val;
  string enum_name;
  initial begin
    enum_val = int'(typed.ENUMED);
    enum_name = typed.ENUMED.name();
  end
endmodule

module fsm #(
    parameter int W = 1
);
  typedef enum logic [1:0] {
    IDLE,
    BUSY
  } state_t;
  localparam state_t START = BUSY;
endmodule

module fsm_checker;
  int start;
  int width;
  initial begin
    start = int'(fsm.START);
    width = fsm.W;
  end
endmodule

bind fsm fsm_checker chk ();

module widths #(
    parameter int SEL = 0,
    parameter UNTYPED = 0,
    parameter NEGATIVE = 0
);
  widths_reader r ();
endmodule

module widths_reader;
  int cast_val;
  int size_cast_val;
  int signed_val;
  int signed_product;
  int unsigned_add;
  initial begin
    cast_val = int'(widths.UNTYPED);
    size_cast_val = 32'(widths.UNTYPED);
    signed_val = int'(widths.NEGATIVE);
    signed_product = widths.NEGATIVE * 2;
    // verilator lint_off WIDTHEXPAND
    unsigned_add = widths.UNTYPED + 32'd1;
    // verilator lint_on WIDTHEXPAND
  end
endmodule
