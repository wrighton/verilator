// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

typedef int int_arr_t[];

class Cls;
  rand int_arr_t arr[];
  function int body();
    return std::randomize(arr[0]) with {arr[0][0] == arr[1][1];};
  endfunction
endclass

module t;
  Cls c;
  initial begin
    c = new;
    void'(c.body());
  end
endmodule
