// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// verilator lint_off DEFPARAM

// A defparam path whose first name is an elaborated generate block names an instance in that
// block (IEEE 1800-2023 23.10.4.2), even if without the block it would name another scope

module m2;
  parameter p = 3;
endmodule

module m3;
  m2 n ();
  defparam x.n.p = 4;  // 'x' is also the instance of m3
  if (1) begin : x
    m2 n ();
  end
  defparam g.n.p = 5;
  if (1) begin : g
    m2 n ();
    m2 n2 ();
    defparam g.n2.p = 6;
  end
endmodule

module m4 #(
    parameter C = 0
);
  m2 n ();
  defparam y.n.p = 7;  // 'y' is also the instance of m4
  if (C) begin : y
    m2 n ();
  end
endmodule

module m5 #(
    parameter C = 0
);
  m2 n ();
  defparam z.n.p = 8;  // 'z' is also the instance of m5
  case (C)
    1: begin : z
      m2 n ();
    end
    default: ;
  endcase
endmodule

module t;
  m3 x ();
  m4 #(.C(1)) y ();
  m5 #(.C(1)) z ();

  initial begin
    `checkd(x.n.p, 3);
    `checkd(x.x.n.p, 4);
    `checkd(x.g.n.p, 5);
    `checkd(x.g.n2.p, 6);
    `checkd(y.n.p, 3);
    `checkd(y.y.n.p, 7);
    `checkd(z.n.p, 3);
    `checkd(z.z.n.p, 8);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
