// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2012 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  logic foo;
  initial foo = 0;

  //   dut #(.W(4)) udut(.*);
  dut #(
      .W(4)
  ) udut (
      .clk(clk),
      .foo(foo)
  );  // Assigning logic to logic array

  // A string literal is converted only to an unpacked array of bytes input
  dut #(
      .W(2)
  ) udut_str (
      .clk(clk),
      .foo("ab")
  );
  string str = "ab";
  bytes_in u_num (.p(16'h6162));
  bytes_in u_str (.p(str));
  bytes_in u_typename (.p($typename(str)));
  bytes2_in u_bytes2 (.p("ab"));
  bytes_out u_out (.p("ab"));
  bytes_ref u_ref (.p("ab"));

endmodule

module bytes_in (
    input byte p[1:0]
);
endmodule

module bytes2_in (
    input byte p[1:0][1:0]
);
endmodule

module bytes_out (
    output byte p[1:0]
);
endmodule

module bytes_ref (
    ref byte p[1:0]
);
endmodule

module dut #(
    parameter W = 1
) (
    input logic clk,
    input logic foo[W-1:0]
);

  genvar i;
  generate
    for (i = 0; i < W; i++) begin
      suba ua (
          .clk(clk),
          .foo(foo[i])
      );
    end
  endgenerate
endmodule

module suba (
    input logic clk,
    input logic foo
);

  always @(posedge clk) $display("foo=%b", foo);

endmodule
