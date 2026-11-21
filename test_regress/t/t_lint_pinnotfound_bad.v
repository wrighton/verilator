// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module a;
  localparam A = 1;
  generate
    if (A == 1) begin
      b b_inst1 (.x(1'b0));  // nonexistent port
      b #(.PX(1'b0)) b_inst2 ();  // nonexistent parameter
      c #(.W(2), .PW(1)) c_inst ();  // nonexistent parameter, with another
    end
  endgenerate
  for (genvar i = 0; i < 2; ++i) begin : g_loop
    b #(.PY(i)) b_inst3 (.y(1'b0));
  end
  case (A)
    1: ifc #(.PZ(1)) ifc_inst ();
    default: ;
  endcase
endmodule

interface ifc;
endinterface

module b;
endmodule

module c;
  parameter W = 1;
endmodule
