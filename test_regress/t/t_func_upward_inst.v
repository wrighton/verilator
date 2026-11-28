// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// Upwards references (IEEE 1800-2023 23.8) resolve from each instance, so read the
// declarations of the instance above each

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  mid #(.W(3)) m3 ();
  mid #(.W(5)) m5 ();
  mid #(.W(7)) m7 ();
  parent_a pa ();
  parent_b pb ();

  initial begin
    #1;
    `checkd(m3.l.ret, 7);
    `checkd(m5.l.ret, 31);
    `checkd(m7.l.ret, 127);
    `checkd(m3.l.arg, 1);
    `checkd(m5.l.arg, 1);
    `checkd(m7.l.arg, 1);
    `checkd(m3.l.def, 3);
    `checkd(m5.l.def, 5);
    `checkd(m7.l.def, 7);
    `checkd(pa.c.named, 210);
    `checkd(pb.c.named, 210);
    `checkd(pa.c.def, 1);
    `checkd(pb.c.def, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module mid #(
    parameter int W = 1
);
  function automatic logic [W-1:0] ret_width();
    return '1;
  endfunction
  function automatic int arg_width(logic [W-1:0] a);
    return int'(a);
  endfunction
  function automatic int default_value(int a = W);
    return a;
  endfunction
  leaf l ();
endmodule

module leaf;
  int ret;
  int arg;
  int def;
  initial begin
    ret = int'(mid.ret_width());  // Return width differs
    arg = mid.arg_width(1);  // Argument width differs
    def = mid.default_value();  // Default value differs
  end
endmodule

module parent_a;
  if (1) begin : cfg
    function automatic int f(int a, int b);
      return 100 * a + b;
    endfunction
    function automatic int g(int a = 1);
      return a;
    endfunction
  end
  by_name c ();
endmodule

module parent_b;
  if (1) begin : cfg
    function automatic int f(int b, int a);
      return 100 * a + b;
    endfunction
    function automatic int g(int a = 2);
      return a;
    endfunction
  end
  by_name c ();
endmodule

module by_name;
  int named;
  int def;
  initial begin
    named = cfg.f(.b(10), .a(2));  // Argument order differs
    def = cfg.g();  // Default value differs
  end
endmodule
