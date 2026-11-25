// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

module t;
  mid #(.W(3)) m3 ();
  mid #(.W(5)) m5 ();
  mid #(.W(7)) m7 ();
  parent_a pa ();
  parent_b pb ();
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
