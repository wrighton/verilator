// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  int m_member = 5;
  int m_a;
  Cls m_other;
  function new(int arg = 1, int from_arg = arg + 1, int from_member = m_member,
               int from_method = get_data(), Cls from_this = this);
    m_a = arg + from_arg + from_member + from_method;
    m_other = from_this;
  endfunction
  virtual function int get_data();
    return 2;
  endfunction
endclass

module t;
  initial begin
    Cls c;
    c = new;
    $stop;
  end
endmodule
