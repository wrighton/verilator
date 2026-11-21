// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// ANSI ports with a net type or implicit data type and no direction are inout
// (IEEE 1800-2023 23.2.2.3); later ports without a direction inherit it

interface net_ifc (
    wire [6:0] a,
    b
);
  assign b = a + 7'd3;
endinterface

module net_dut (
    inout wire [6:0] a,
    inout wire [6:0] b
);
endmodule

bind net_dut net_ifc bound_ifc (
    .a(a),
    .b(b)
);

module range_mod (
    [6:0] x,
    wire [6:0] y
);
  assign y = x ^ 7'h55;
endmodule

module signed_mod (
    signed s,
    tri signed [4:0] d
);
  assign d = s ? -5'sd3 : 5'sd5;
endmodule

module t;
  logic [6:0] stim = 7'h11;

  // Test: interface instance
  wire [6:0] ifc_a, ifc_b;
  assign ifc_a = stim;
  net_ifc direct_ifc (
      .a(ifc_a),
      .b(ifc_b)
  );

  // Test: interface bound into a module
  wire [6:0] bind_a, bind_b;
  assign bind_a = ~stim;
  net_dut dut (
      .a(bind_a),
      .b(bind_b)
  );

  // Test: module with implicit data type ports
  wire [6:0] range_x, range_y;
  assign range_x = stim + 7'd1;
  range_mod range_u (
      .x(range_x),
      .y(range_y)
  );

  // Test: module with signed ports
  wire signed_s;
  wire signed [4:0] signed_d;
  assign signed_s = stim[0];
  signed_mod signed_u (
      .s(signed_s),
      .d(signed_d)
  );

  initial begin
    for (int i = 0; i < 9; ++i) begin
      stim = stim * 7'd5 + 7'd13;
      #1;
      `checkh(ifc_b, stim + 7'd3);
      `checkh(direct_ifc.a, stim);
      `checkh(bind_b, ~stim + 7'd3);
      `checkh(dut.bound_ifc.a, ~stim);
      `checkh(range_y, (stim + 7'd1) ^ 7'h55);
      `checkh(signed_d, stim[0] ? -5'sd3 : 5'sd5);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
