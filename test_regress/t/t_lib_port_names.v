// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`ifndef LIB_USE
// Ports named like the DPI functions of the wrapper of the library 'sub'
module sub (
    input logic clk,
    input logic sub_protectlib_check_hash,
    input logic sub_protectlib_create,
    input logic sub_protectlib_combo_update,
    output logic sub_protectlib_seq_update,
    output logic sub_protectlib_combo_ignore,
    output logic sub_protectlib_final,
    output logic q
);
`ifndef LIB_CREATE
  /*verilator hier_block*/
`endif
  always_ff @(posedge clk)
    q <= sub_protectlib_check_hash ^ sub_protectlib_create ^ sub_protectlib_combo_update;
  assign sub_protectlib_seq_update = ~q;
  assign sub_protectlib_combo_ignore = ~q;
  assign sub_protectlib_final = ~q;
endmodule
`endif

`ifndef LIB_CREATE
module top;
  logic clk = 1'b0;
  logic q;
  logic sub_protectlib_seq_update_o;
  logic sub_protectlib_combo_ignore_o;
  logic sub_protectlib_final_o;
  sub u_sub (
      .clk(clk),
      .sub_protectlib_check_hash(1'b1),
      .sub_protectlib_create(1'b1),
      .sub_protectlib_combo_update(1'b1),
      .sub_protectlib_seq_update(sub_protectlib_seq_update_o),
      .sub_protectlib_combo_ignore(sub_protectlib_combo_ignore_o),
      .sub_protectlib_final(sub_protectlib_final_o),
      .q(q)
  );
  initial begin
    #1 clk = 1'b1;
    #1;
    `checkh(q, 1'b1);
    `checkh(sub_protectlib_seq_update_o, 1'b0);
    `checkh(sub_protectlib_combo_ignore_o, 1'b0);
    `checkh(sub_protectlib_final_o, 1'b0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
`endif
