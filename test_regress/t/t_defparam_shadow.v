// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A path starting with the top module's name names a nearer instance of that name (IEEE
// 1800-2023 23.8), so does not set the top's parameter that a defparam from $root sets

module leaf #(
    parameter int P = 0
);
endmodule

module bank;
  leaf #(.P(9)) u ();
endmodule

module livecfg;
  defparam $root.t.u.P = 7;
endmodule

module shadowcfg;
  defparam t.u.P = 9;
endmodule

module holder;
  livecfg c ();
endmodule

module box #(
    parameter int TAG = 0
);
  bank t ();
  shadowcfg c ();
  holder h ();
endmodule

module t;
  leaf u ();
  box #(.TAG(1)) a ();
  box #(.TAG(2)) b ();
  if (0) begin : unbuilt
    shadowcfg c ();
  end
  initial begin
    `checkd(u.P, 7);
    `checkd(a.t.u.P, 9);
    `checkd(b.t.u.P, 9);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
