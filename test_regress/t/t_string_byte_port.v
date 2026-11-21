// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on


// String literals connected to unpacked byte array input ports, converted as in an
// assignment, IEEE 1800-2023 10.8 and 5.9
typedef byte bytes4_t[4];

module sub_asc (
    input byte p[0:2],
    output bit [23:0] o
);
  assign o = {p[0], p[1], p[2]};
endmodule

module sub_desc (
    input byte p[5:2],
    output bit [31:0] o
);
  assign o = {p[5], p[4], p[3], p[2]};
endmodule

module sub_typedef (
    input bytes4_t p,
    input logic [7:0] l[1:3],
    output bit [31:0] o,
    output logic [23:0] lo
);
  assign o = {p[0], p[1], p[2], p[3]};
  assign lo = {l[1], l[2], l[3]};
endmodule

module sub_param #(
    parameter byte P[0:1] = "pq"
) (
    output bit [15:0] o
);
  assign o = {P[0], P[1]};
endmodule

interface ifc (
    input byte p[1:0]
);
endinterface

module t (
    input clk
);

  // Test: shorter and longer strings, named and positional connections
  bit [23:0] asc_short;
  bit [23:0] asc_long;
  bit [23:0] asc_pos;
  sub_asc u_asc_short (
      .p("a"),
      .o(asc_short)
  );
  sub_asc u_asc_long (
      .p("abcd"),
      .o(asc_long)
  );
  sub_asc u_asc_pos (
      "xy",
      asc_pos
  );

  // Test: descending non-zero bounds, NUL and high characters, empty string
  bit [31:0] desc_eq;
  bit [31:0] desc_chars;
  bit [31:0] desc_empty;
  sub_desc u_desc_eq (
      .p("wxyz"),
      .o(desc_eq)
  );
  sub_desc u_desc_chars (
      .p("\000\377\200"),
      .o(desc_chars)
  );
  sub_desc u_desc_empty (
      .p(""),
      .o(desc_empty)
  );

  // Test: typedef array and four-state element types
  bit [31:0] typedef_o;
  logic [23:0] typedef_lo;
  sub_typedef u_typedef (
      .p("ab"),
      .l("m\000"),
      .o(typedef_o),
      .lo(typedef_lo)
  );

  // Test: ordinary array variable connection
  byte var_bytes[5:2] = "copy";
  bit [31:0] desc_var;
  sub_desc u_desc_var (
      .p(var_bytes),
      .o(desc_var)
  );

  // Test: parameter default and override
  bit [15:0] param_default;
  bit [15:0] param_override;
  sub_param u_param_default (.o(param_default));
  sub_param #(.P("x")) u_param_override (.o(param_override));

  // Test: interface port
  ifc u_ifc (.p("ij"));

  // Check after the continuous assignments have settled
  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 1) begin
      `checkh(asc_short, {"a", 16'h0});
      `checkh(asc_long, "abc");
      `checkh(asc_pos, {"xy", 8'h0});
      `checkh(desc_eq, "wxyz");
      `checkh(desc_chars, 32'h00ff8000);
      `checkh(desc_empty, 32'h0);
      `checkh(typedef_o, {"ab", 16'h0});
      `checkh(typedef_lo, {"m", 16'h0});
      `checkh(desc_var, "copy");
      `checkh(param_default, "pq");
      `checkh(param_override, {"x", 8'h0});
      `checkh(u_ifc.p[1], "i");
      `checkh(u_ifc.p[0], "j");
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
