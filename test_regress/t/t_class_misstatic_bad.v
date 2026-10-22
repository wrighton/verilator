// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  int m_field = get_ok();
  function int get_ok();
    return 1;
  endfunction
  function void nonstatic();
  endfunction
  function Cls nonstatic_retcls();
    return null;
  endfunction
  static function void isst();
  endfunction
  int m_var;
  int m_init = m_var;
  class Nested;
    function int get_outer();
      return m_var;  // <--- bad static ref
    endfunction
  endclass
endclass

class Bar;
  function void bar();
    Cls::nonstatic();  // <--- bad static ref
    Cls::nonstatic_retcls();  // <--- bad static ref
    Cls::isst();
    $display(Cls::m_var);  // <--- bad static ref
  endfunction
endclass

class Extends extends Cls;
  function void ok();
    nonstatic();
    isst();
  endfunction
  static function void extstatic();
    nonstatic();  // <--- bad static ref
    isst();
  endfunction
  function new();
    Cls c = super.nonstatic_retcls();
  endfunction
endclass

module t;
  function void nonclassfunc();
    Cls::nonstatic();  // <--- bad static ref
    Cls::isst();
    $display(Cls::m_var);  // <--- bad static ref
  endfunction
  initial begin
    automatic Bar obj = new();
    obj.bar();
    Cls::nonstatic();  // <--- bad static ref
    Cls::isst();
    Extends::isst();
    $display(Cls::m_var);  // <--- bad static ref
    $display($bits(Cls::m_var));
    $stop;
  end
endmodule
