// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A defparam without a dot sets a parameter of its own module (IEEE 1800-2023 23.10.1),
// overriding parameter value assignments of the instances (IEEE 1800-2023 23.10)

module ansi #(
    parameter bit EN = 1'b1,
    parameter int Q = 1,
    parameter int W = 4
) (
    input int in,
    output int out
);
  defparam EN = 1'b0, W = 5;
  defparam W = 2 * Q;  // Last defparam wins
  assign out = EN ? 0 : in * W;
endmodule

module nonansi (
    input int in,
    output int out
);
  parameter int W = 4;
  defparam W = 7;
  assign out = in * W;
endmodule

module nodefault #(
    parameter int N
) (
    input int in,
    output int out
);
  defparam N = 3;
  assign out = in * N;
endmodule

module t;
  parameter int TP = 1;
  defparam TP = 4;  // In the top module
  int in;
  int out_a, out_b, out_c, out_d, out_e, out_f;
  ansi u_a (
      .in(in),
      .out(out_a)
  );
  ansi #(
      .EN(1'b1),
      .Q(3),
      .W(100)
  ) u_b (
      .in(in),
      .out(out_b)
  );
  nonansi #(9) u_c (
      .in(in),
      .out(out_c)
  );
  nonansi u_d (
      .in(in),
      .out(out_d)
  );
  nonansi u_e (
      .in(in),
      .out(out_e)
  );
  defparam u_e.W = 11;  // A defparam from above also applies
  nodefault #(.N(5)) u_f (
      .in(in),
      .out(out_f)
  );

  initial begin
    for (in = 1; in < 4; ++in) begin
      #1;
      `checkd(out_a, in * 2);
      `checkd(out_b, in * 6);
      `checkd(out_c, in * 7);
      `checkd(out_d, in * 7);
      `checkd(out_e, in * 11);
      `checkd(out_f, in * 3);
      `checkd(in * TP, in * 4);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
