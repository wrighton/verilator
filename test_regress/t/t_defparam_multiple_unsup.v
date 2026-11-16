// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  parameter P = 0;
endmodule

module mid;
  sub s ();
endmodule

module t #(
    parameter W = 0
);
  // Generate blocks of the same name, each with a defparam to the same parameter
  if (W == 0) begin
    mid m ();
    defparam m.s.P = 1;
  end else begin
    mid m ();
    defparam m.s.P = 2;
  end
  case (W)
    0: begin : g
      mid m ();
      defparam m.s.P = 3;
    end
    default: begin : g
      mid m ();
      defparam m.s.P = 4;
    end
  endcase
endmodule
