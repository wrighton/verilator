// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A default value with Z bits of an input port applies only when the port is not connected
// (IEEE 1800-2023 23.2.2.4): then the Z bits are a high impedance contribution, here to a
// pulled up net, also from a variable, which holds Z. A connected port takes only its
// connection.
module t (
    input clk
);
  int cyc = 0;
  logic [1:0] v = 2'd0;
  wire pull_plain_o;
  wire [1:0] conn_plain_o;
  wire pull_logic_o;
  wire [1:0] conn_logic_o;
  wire pull_var_o;
  wire [1:0] conn_var_o;
  wire pull_wire_o;
  wire [1:0] conn_wire_o;
  wire pull_tri1_o;
  wire [1:0] conn_tri1_o;
  wire pull_wand_o;
  wire [1:0] conn_wand_o;
  pull_plain u_pull_plain (.y(pull_plain_o));
  conn_plain u_conn_plain (
      .a(v),
      .y(conn_plain_o)
  );
  pull_logic u_pull_logic (.y(pull_logic_o));
  conn_logic u_conn_logic (
      .a(v),
      .y(conn_logic_o)
  );
  pull_var u_pull_var (.y(pull_var_o));
  conn_var u_conn_var (
      .a(v),
      .y(conn_var_o)
  );
  pull_wire u_pull_wire (.y(pull_wire_o));
  conn_wire u_conn_wire (
      .a(v),
      .y(conn_wire_o)
  );
  pull_tri1 u_pull_tri1 (.y(pull_tri1_o));
  conn_tri1 u_conn_tri1 (
      .a(v),
      .y(conn_tri1_o)
  );
  pull_wand u_pull_wand (.y(pull_wand_o));
  conn_wand u_conn_wand (
      .a(v),
      .y(conn_wand_o)
  );
  // Modules with instances that connect a port and that do not
  wire pull_var_c_o;
  pull_var u_pull_var_c (
      .a(v[0]),
      .y(pull_var_c_o)
  );
  wire [1:0] mix_c_o;
  wire [1:0] mix_u_o;
  mix_wire u_mix_c (
      .a(v),
      .y(mix_c_o)
  );
  mix_wire u_mix_u (.y(mix_u_o));

  wire var_o;
  sub_var u_var (.y(var_o));
  wire eq_var_o;
  sub_eq_var u_eq_var (.y(eq_var_o));

  // A Z default of a net, with sibling instances that connect the port and that do not
  wire sib_c_o, sib_u_o, par_c_o, par_u_o;
  pull_sib u_sib_c (
      .a(v[0]),
      .y(sib_c_o)
  );
  pull_sib u_sib_u (.y(sib_u_o));
  pull_par #(.P(3)) u_par_c (
      .a(v[0]),
      .y(par_c_o)
  );
  pull_par #(.P(3)) u_par_u (.y(par_u_o));
  wire z_o;
  sub_z u_z (.y(z_o));
  wire if_o;
  link_if u_if ();
  recv u_recv (
      .intf(u_if),
      .y(if_o)
  );

  always @(posedge clk) begin
    cyc <= cyc + 1;
    v <= v + 2'd1;
    `checkh(pull_plain_o, 1'b1);
    `checkh(conn_plain_o, v);
    `checkh(pull_logic_o, 1'b1);
    `checkh(conn_logic_o, v);
    `checkh(pull_var_o, 1'b1);
    `checkh(conn_var_o, v);
    `checkh(pull_wire_o, 1'b1);
    `checkh(conn_wire_o, v);
    `checkh(pull_tri1_o, 1'b1);
    `checkh(conn_tri1_o, v);
    `checkh(pull_wand_o, 1'b1);
    `checkh(conn_wand_o, v);
    `checkh(pull_var_c_o, v[0]);
    `checkh(mix_c_o, v);
    `checkh(mix_u_o, 2'd2);
    `checkh(var_o, 1'b1);
    `checkh(eq_var_o, 1'b1);
    `checkh(sib_c_o, v[0]);
    `checkh(sib_u_o, 1'b1);
    `checkh(par_c_o, v[0]);
    `checkh(par_u_o, 1'b1);
    `checkh(z_o, 1'b1);
    `checkh(if_o, 1'b1);
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module pull_plain (
    input a = 1'bz,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module conn_plain (
    input [1:0] a = 2'b1z,
    output wire [1:0] y
);
  assign y = a;
endmodule

module pull_logic (
    input logic a = 1'bz,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module conn_logic (
    input logic [1:0] a = 2'b1z,
    output wire [1:0] y
);
  assign y = a;
endmodule

module pull_var (
    input var logic a = 1'bz,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module conn_var (
    input var logic [1:0] a = 2'b1z,
    output wire [1:0] y
);
  assign y = a;
endmodule

module pull_wire (
    input wire a = 1'bz,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module conn_wire (
    input wire [1:0] a = 2'b1z,
    output wire [1:0] y
);
  assign y = a;
endmodule

module pull_tri1 (
    input tri1 a = 1'bz,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module conn_tri1 (
    input tri1 [1:0] a = 2'b1z,
    output wire [1:0] y
);
  assign y = a;
endmodule

module pull_wand (
    input wand a = 1'bz,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module conn_wand (
    input wand [1:0] a = 2'b1z,
    output wire [1:0] y
);
  assign y = a;
endmodule

module mix_wire (
    input wire [1:0] a = 2'b10,
    output wire [1:0] y
);
  assign y = a;
endmodule

module pull_sib (
    input wire a = 1'bz,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module pull_par #(
    parameter int P = 0
) (
    input wire a = 1'bz,
    output wire y
);
  tri [P:0] bus;
  pullup (bus[0]);
  assign bus[0] = a;
  assign y = bus[0];
endmodule

module sub_eq_var (
    input var logic a = 1'bz,
    output wire y
);
  assign y = (a === 1'bz);
endmodule

module sub_var (
    input var logic a = 1'bz,
    output wire y
);
  tri bus;
  pullup (bus);
  assign bus = a;
  assign y = bus;
endmodule

module sub_z (
    input wire a = 1'bz,
    output wire y
);
  assign y = (a === 1'bz);
endmodule

interface link_if (
    input logic pd = 1'bz
);
  tri1 link;
  assign link = pd;
  modport receive(input link);
endinterface

module recv (
    link_if.receive intf,
    output wire y
);
  assign y = intf.link;
endmodule
