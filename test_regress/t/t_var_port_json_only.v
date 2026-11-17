// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2021 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// This checks IEEE ports work correctly, we use XML output to make it easy to
// see all attributes are propagated

// verilator lint_off MULTITOP

module mh0 (wire x_inout_wire_logic);
endmodule
`ifndef VERILATOR
module mh1 (integer x_inout_wire_integer);
endmodule
`endif
module mh2 (inout integer x_inout_wire_integer);
endmodule
module mh3 ([5:0] x_inout_wire_logic_p6);
endmodule
module mh5 (input x_input_wire_logic);
endmodule
module mh6 (input var x_input_var_logic);
endmodule
module mh7 (input var integer x_input_var_integer);
endmodule
module mh8 (output x_output_wire_logic);
endmodule
module mh9 (output var x_output_var_logic);
endmodule
module mh10(output signed [5:0] x_output_wire_logic_signed_p6);
endmodule
module mh11(output integer x_output_var_integer);
endmodule
module mh12(ref [5:0] x_ref_logic_p6);
endmodule
module mh13(ref x_ref_var_logic_u6 [5:0]);
endmodule
module mh14(wire x_inout_wire_logic, y_inout_wire_logic_p8 [7:0]);
endmodule
`ifndef VERILATOR
module mh15(integer x_inout_wire_integer, signed [5:0] y_inout_wire_logic_signed6);
endmodule
`endif
module mh16([5:0] x_inout_wire_logic_p6, wire y_inout_wire_logic);
endmodule
module mh17(input var integer x_input_var_integer, wire y_input_wire_logic);
endmodule
module mh18(output var x_output_var_logic, input y_input_wire_logic);
endmodule
module mh19(output signed [5:0] x_output_wire_logic_signed_p6, integer y_output_var_integer);
endmodule
module mh20(ref [5:0] x_ref_var_logic_p6, y_ref_var_logic_p6);
endmodule
module mh21(ref ref_var_logic_u6 [5:0], y_ref_var_logic);
endmodule

// Net type or implicit data type with no direction, after the IEEE examples
typedef logic [2:0] mn_t;
module mn0 (wire logic [6:0] x_inout_wire_logic_p7);
endmodule
module mn1 (wire integer x_inout_wire_integer, wire mn_t y_inout_wire_mn_t);
endmodule
module mn2 (signed x_inout_wire_logic_signed, signed [4:0] y_inout_wire_logic_signed_p5);
endmodule
module mn3 (wire signed x_inout_wire_logic_signed);
endmodule
module mn4 (input [2:0] x_input_wire_logic_p3, wire y_input_wire_logic,
            signed z_input_wire_logic_signed, [1:0] w_input_wire_logic_p2);
endmodule
module mn5 (output [2:0] x_output_wire_logic_p3, wire y_output_wire_logic,
            signed [1:0] z_output_wire_logic_signed_p2);
endmodule
