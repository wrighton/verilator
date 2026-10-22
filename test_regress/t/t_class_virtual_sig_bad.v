// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef int int_t;

class Base;
  virtual function void f_type(int a);
  endfunction
  virtual function void f_count(int a);
  endfunction
  virtual function void f_dir(input int a);
  endfunction
  virtual function int f_ret();
    return 0;
  endfunction
  virtual function int f_void();
    return 0;
  endfunction
  virtual function void f_task();
  endfunction
  virtual task t_func();
  endtask
  virtual function int f_class_ret();
    return 0;
  endfunction
  virtual function void f_nonvoid();
  endfunction
  virtual function void f_deep(int a);
  endfunction
  virtual function Base f_ok_derived_ret();
    return null;
  endfunction
  virtual function void f_ok_typedef(int a, ref int b);
  endfunction
  function void f_ok_nonvirtual(int a);
  endfunction
endclass

class Mid extends Base;
endclass

class Cls extends Mid;
  virtual function void f_type(byte a);  // <--- Error: type
  endfunction
  virtual function void f_count(int a, int b);  // <--- Error: count
  endfunction
  virtual function void f_dir(output int a);  // <--- Error: direction
  endfunction
  virtual function byte f_ret();  // <--- Error: return type
    return 0;
  endfunction
  virtual function void f_void();  // <--- Error: return type
  endfunction
  virtual task f_task();  // <--- Error: task vs function
  endtask
  virtual function void t_func();  // <--- Error: function vs task
  endfunction
  virtual function Cls f_class_ret();  // <--- Error: return type
    return null;
  endfunction
  virtual function int f_nonvoid();  // <--- Error: return type
    return 0;
  endfunction
  function void f_deep(bit a);  // <--- Error: type (through Mid)
  endfunction
  virtual function Cls f_ok_derived_ret();
    return null;
  endfunction
  virtual function void f_ok_typedef(int_t a, ref int_t b);
    int local_var;
  endfunction
  function void f_ok_nonvirtual(string a, int b);
  endfunction
endclass

virtual class VBase;
  pure virtual function void f_pure(int a);
endclass

class VCls extends VBase;
  virtual function void f_pure(string a);  // <--- Error: type
  endfunction
endclass

interface class Ifc;
  pure virtual function int f_ifc(int a);
endclass

class ICls implements Ifc;
  virtual function int f_ifc(int a, int b);  // <--- Error: count
    return 0;
  endfunction
endclass

interface class FwdIfc;
  pure virtual task t_fwd(int a);
endclass

class FwdBase;
  virtual task t_fwd(int a);
  endtask
endclass

class FwdImpl extends FwdBase implements FwdIfc;
endclass

class FwdCls extends FwdImpl;
  virtual task t_fwd(int a);
  endtask
endclass

module t;
  initial $stop;
endmodule
