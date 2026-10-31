// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Base;
  int b[30];
  int b0, b1, b2, b3, b4, b5, b6, b7, b8, b9;
  function void set(int v);
    b0 = v;
    b9 = v + 9;
  endfunction
endclass

class Derived extends Base;
  int d0, d1, d2, d3, d4, d5, d6, d7, d8, d9;
  function int get();
    d9 = b9 + 1;  // Base class member reference
    return d9;
  endfunction
endclass

module sub #(
    parameter int N = 1
) (
    input clk,
    input int cyc
);
  /*verilator no_inline_module*/
  for (genvar i = 0; i < N; ++i) begin : gen
    int r;
    always @(posedge clk) begin
      r <= cyc * (i + 1);
      if (cyc == 5) `checkh(r, 4 * (i + 1));
    end
  end
endmodule

module t (
    input clk
);
  int cyc = 0;
  int pub  /*verilator public_flat_rw*/;
  Derived obj = new;

  // More than 3*3 trivially constructible members with --comp-limit-members 3 are in named
  // structs, fewer in anonymous structs
  sub #(.N(40)) u_40 (.*);
  sub #(.N(10)) u_10 (.*);
  sub #(.N(9)) u_9 (.*);
  sub #(.N(7)) u_7 (.*);
  sub #(.N(8)) u_8 (.*);

  for (genvar i = 0; i < 40; ++i) begin : gen
    int r;
    int pubr  /*verilator public_flat_rw*/;
    always @(posedge clk) begin
      r <= cyc + i;
      pubr <= r;
      if (cyc == 5) `checkh(r, 4 + i);
      if (cyc == 5) `checkh(pubr, 3 + i);
    end
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    pub <= gen[37].r;
    obj.set(cyc);
    if (cyc == 6) begin
      `checkh(pub, 41);
      `checkh(obj.get(), 16);
      `checkh(obj.b0, 6);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
