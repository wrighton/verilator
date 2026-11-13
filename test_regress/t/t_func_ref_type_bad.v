// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The actual of a ref argument must have a type equivalent to the formal (IEEE 1800-2023 13.5.2)

task automatic set_real(ref real r);
  r = 1.0;
endtask

task automatic set_str(ref string o);
  o = "ab";
endtask

function automatic string get_str(const ref string s);
  return s;
endfunction

module t;
  logic [31:0] l;
  int i;
  initial begin
    set_real(l);  // Bad
    set_real(i);  // Bad
    void'(get_str(i));  // Bad
    set_str(i);  // Bad
  end
endmodule
