// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Automatic variables shall not be written with non-blocking, continuous or procedural continuous
// assignments, nor non-static class properties with continuous or procedural continuous
// assignments (IEEE 1800-2023 6.21)

class Cls;
  static int s_ok1;
  static int s_ok2;
  int m_bad1;
  int m_ok2;
endclass

module t (
    input clk
);

  Cls c;

  assign c.m_bad1 = 2;  // <--- Error: continuous class non-static
  // Only one simulator fails on this, probably not legal
  // assign Cls::s_ok1 = 2;  // OK: continuous class static

  logic ok_7;
  task mt(output o);  // OK: function output
    o <= 1;
  endtask

  always @(posedge clk) begin
    Cls::s_ok2 <= 2;  // OK: nonblocking class static
    c.m_ok2 <= 2;  // OK: nonblocking class non-static
    mt(ok_7);
    $stop;
  end

  // Nor reading automatic variables in procedural continuous assignments
  reg g;
  task automatic tsk;
    reg l;
    begin : cont_block
      // verilator lint_off IEEEMAYDEPRECATE
      assign g = signed'(l);  // Error: procedural continuous read of automatic
      // verilator lint_on IEEEMAYDEPRECATE
    end
  endtask

  // The dynarray element is only read, to get the handle
  Cls ok_arr_h[2][];
  always @(posedge clk) begin
    ok_arr_h[0][0].m_ok2 <= 2;  // OK: nonblocking class non-static
  end

  // Also a part of them
  always @(posedge clk) begin
    automatic int bad_auto;
    bad_auto[3:0] <= 2;  // Error: nonblocking automatic, part of it
    c.m_ok2[3:0] <= 2;  // OK: nonblocking class non-static, part of it
  end

  // Ports of automatic subroutines, including class methods, are automatic variables
  task automatic tbad(int bad_a, output int bad_o, ref int bad_r);
    bad_a <= 1;  // Error: nonblocking automatic task input
    bad_o <= 1;  // Error: nonblocking automatic task output
    bad_r <= 1;  // Error: nonblocking automatic task ref
    mt.o <= 1;  // OK: nonblocking static task output, by hierarchical reference
  endtask
  class ClsM;
    function void fbad(int bad_m);
      bad_m <= 1;  // Error: nonblocking class method argument
    endfunction
  endclass

endmodule
