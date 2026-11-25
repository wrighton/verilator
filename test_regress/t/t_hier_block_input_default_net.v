// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A hierarchical block's input port with a default value with Z bits, also with the enables of
// tristate inputs: a connected instance takes only its connection, and an unconnected one the
// default, its Z bits a value, as for any input of a model
module t (
    input clk
);
  int cyc = 0;
  logic [3:0] v = 4'd4;
  wire [3:0] conn_o;
  wire [3:0] dflt_o;
  sub u_conn (
      .a(v),
      .y(conn_o)
  );
  sub u_dflt (.y(dflt_o));

  always @(posedge clk) begin
    cyc <= cyc + 1;
    v <= v + 4'd1;
    `checkh(conn_o, v);
    `checkh(dflt_o, 4'h8);
    if (cyc == 3) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module sub (
    input wire [3:0] a = 4'b1x0z,
    output wire [3:0] y
);
  /*verilator hier_block*/
  assign y = a;
endmodule
