// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Geza Lore
// SPDX-License-Identifier: CC0-1.0

module t;

  logic [31:0] packed_data_32;
  byte byte_in[4];
  logic [3:0] x = 4'($random());

  initial begin
    packed_data_32 = {<<$random{byte_in}};
    packed_data_32 = {<<x{byte_in}};
  end

  // An inout port connection is not an assignment, so a stream is not valid
  wire [31:0] io_bus;
  sub_inout i_sub_inout (.io({>>{io_bus}}));

  // A ref port connection is a hierarchical reference, not an assignment,
  // so a stream is not valid
  logic [31:0] ref_var;
  sub_ref i_sub_ref (.r({>>{ref_var}}));
  sub_assoc i_sub_assoc (.p({>>{ref_var}}));
  sub_wild i_sub_wild (.p({>>{ref_var}}));

  // Each element of a dynamically sized stream source is wider than the fixed size target
  typedef byte byte_q_t[$];
  byte_q_t byte_q;
  int int_q[$];
  byte byte_d[];
  logic [3:0] narrow;
  byte one_byte[1];
  byte byte4_q[$][4];
  logic [15:0] narrow16;
  initial begin
    narrow = {>>{byte_q}};
    one_byte = {>>{int_q}};
    narrow = {<<4{byte_d}};
    narrow16 = {>>{byte4_q}};
  end

endmodule

module sub_inout (
    inout wire [31:0] io
);
endmodule

module sub_ref (
    ref logic [31:0] r
);
endmodule

module sub_assoc (
    input byte p[int]
);
endmodule

module sub_wild (
    input byte p[*]
);
endmodule
