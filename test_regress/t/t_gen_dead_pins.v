// DESCRIPTION: Verilator: Verilog Test module
//
// Instances in generate blocks that are not elaborated may connect ports and parameters the
// module does not have (IEEE 1800-2023 27.5).
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifc;
  logic [3:0] data;
endinterface

module leaf #(
    parameter int WIDTH = 1
) (
    input logic [WIDTH-1:0] in,
    output logic [WIDTH-1:0] out
);
  assign out = in;
endmodule

module mid #(
    parameter bit ISOLATE = 1'b0,
    parameter int SEL = 0,
    parameter int N = 0
) (
    input logic [3:0] in,
    output logic [3:0] out
);
  ifc bus ();
  if (ISOLATE == 1'b1) begin : g_pipe
    leaf #(.WIDTH(4), .TYPE(1)) u_leaf (.in(in), .out(out), .scan(1'b0), .bus(bus));
  end else begin : g_bypass
    leaf #(.WIDTH(4)) u_leaf (.in(~in), .out(out));
  end
  case (SEL)
    1: leaf #(.NOPE(2)) u_case (.in(in), .out(), .nope(in));
    2: ifc #(.NOPE(2)) u_ifc ();
    default: ;
  endcase
  for (genvar i = 0; i < N; ++i) begin : g_loop
    leaf #(.NOPE(i)) u_loop (.in(in), .out(), .nope(in));
  end
endmodule

module t;
  logic [3:0] in;
  logic [3:0] out;
  mid u_mid (.in(in), .out(out));
  logic [3:0] out2;
  mid #(.SEL(3)) u_mid2 (.in(in), .out(out2));

  initial begin
    in = 4'h5;
    #1;
    `checkh(out, 4'ha);
    `checkh(out2, 4'ha);
    in = 4'h3;
    #1;
    `checkh(out, 4'hc);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
