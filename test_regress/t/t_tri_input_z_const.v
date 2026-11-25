// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An input port connected to a constant with Z bits is high impedance there in its module,
// while another instance of the module connects a driven value
module t (
    input clk
);
  int cyc = 0;
  logic [3:0] v = 4'd0;
  wire pull_z_o, pull_d_o, eq_z_o, eq_d_o;
  wire [3:0] wide_z_o, wide_d_o;

  pull u_pull_z (
      .a(1'bz),
      .y(pull_z_o)
  );
  pull u_pull_d (
      .a(v[0]),
      .y(pull_d_o)
  );
  eq u_eq_z (
      .a(1'bz),
      .y(eq_z_o)
  );
  eq u_eq_d (
      .a(v[0]),
      .y(eq_d_o)
  );
  wide u_wide_z (
      .a(4'b1z0z),
      .y(wide_z_o)
  );
  wide u_wide_d (
      .a(v),
      .y(wide_d_o)
  );

  always @(posedge clk) begin
    cyc <= cyc + 1;
    v <= v + 4'd1;
    `checkh(pull_z_o, 1'b1);
    `checkh(pull_d_o, v[0]);
    `checkh(eq_z_o, 1'b1);
    `checkh(eq_d_o, 1'b0);
    `checkh(wide_z_o, 4'b1101);
    `checkh(wide_d_o, v);
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module pull (
    input wire a,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module eq (
    input wire a,
    output wire y
);
  assign y = (a === 1'bz);
endmodule

module wide (
    input wire [3:0] a,
    output wire [3:0] y
);
  tri1 [3:0] bus;
  assign bus = a;
  assign y = bus;
endmodule
