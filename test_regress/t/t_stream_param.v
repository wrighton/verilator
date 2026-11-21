// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Streaming concatenations as parameter override values (assignment-like, IEEE 1800-2023 10.8)

module sub #(
    parameter bit [15:0] P = 0,
    parameter U = 0
) (
    output bit [15:0] p,
    output int ubits,
    output int u
);
  assign p = P;
  assign ubits = $bits(U);
  assign u = int'(U);
endmodule

interface ifc #(
    parameter bit [11:0] P = 0
);
endinterface

class Cls #(
    parameter bit [15:0] P = 0
);
  static function bit [15:0] get();
    return P;
  endfunction
endclass

module t;
  localparam bit [15:0] B = 16'h1234;
  localparam bit [11:0] C = 12'habc;

  bit [15:0] p_named, p_pos, p_right, p_def;
  int ubits_named, u_named, ubits_pos, u_pos;

  sub #(
      .P({<<8{B}}),
      .U({<<{4'b0001}})
  ) u_named_i (
      .p(p_named),
      .ubits(ubits_named),
      .u(u_named)
  );
  sub #({>>4{B}}, {<<4{C}}) u_pos_i (
      .p(p_pos),
      .ubits(ubits_pos),
      .u(u_pos)
  );
  sub #(.P({>>{B}})) u_right_i (
      .p(p_right),
      .ubits(),
      .u()
  );
  sub u_def_i (
      .p(p_def),
      .ubits(),
      .u()
  );
  defparam u_def_i.P = {<<4{B}};

  ifc #(.P({<<4{C}})) i_ifc ();

  initial begin
    #1;
    `checkh(p_named, 16'h3412);
    `checkd(ubits_named, 4);
    `checkd(u_named, 8);
    `checkh(p_pos, 16'h1234);
    `checkd(ubits_pos, 12);
    `checkh(u_pos, 32'hcba);
    `checkh(p_right, 16'h1234);
    `checkh(p_def, 16'h4321);
    `checkh(i_ifc.P, 12'hcba);
    `checkh(Cls#({<<8{B}})::get(), 16'h3412);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
