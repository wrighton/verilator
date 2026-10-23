// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef struct {
  logic x;
  logic y;
} us_t;

module sub (
    output logic y
);
  assign y = 1'b0;
endmodule

module t (
    input clk,
    input a,
    input b
);
  logic v_assigns;
  assign v_assigns = a;
  assign v_assigns = b;  // <--- Warning: two continuous assignments

  logic v_ports;
  sub u_ports1 (.y(v_ports));
  sub u_ports2 (.y(v_ports));  // <--- Warning: two output ports

  logic v_port_assign;
  sub u_port_assign (.y(v_port_assign));
  assign v_port_assign = a;  // <--- Warning: output port and continuous assignment

  logic v_port_initial;
  sub u_port_initial (.y(v_port_initial));
  initial v_port_initial = 1'b1;  // <--- Warning: output port and initial

  logic v_always_port;
  always @(posedge clk) v_always_port <= a;
  sub u_always_port (.y(v_always_port));  // <--- Warning: always and output port

  logic v_ff_port;
  always_ff @(posedge clk) v_ff_port <= a;
  sub u_ff_port (.y(v_ff_port));  // <--- Warning (existing): always_ff and output port

  // Legal: different bits, elements or members, or nets
  logic [1:0] v_bits;
  assign v_bits[0] = a;
  assign v_bits[1] = b;
  sub u_bits0 (.y(v_bits[0]));
  logic [1:0] v_bits2;
  sub u_bits20 (.y(v_bits2[0]));
  sub u_bits21 (.y(v_bits2[1]));
  logic v_arr[2];
  assign v_arr[0] = a;
  assign v_arr[1] = b;
  us_t v_struct;
  assign v_struct.x = a;
  assign v_struct.y = b;
  wire w_net;
  assign w_net = a;
  assign w_net = b;
endmodule
