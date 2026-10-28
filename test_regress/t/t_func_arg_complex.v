// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Cls;
  enum {
    ONEK = 1000,
    TWOK = 2000
  } sev_t;
  int m_default_data;
  function int trigger(int data = get_default_data());
    return data;
  endfunction

  task triggert(output int o, input int data = get_default_data());
    o = data;
  endtask

  virtual function int get_default_data();
    return m_default_data;
  endfunction

  function int uvm_report(int severity, int verbosity = (severity == 1) ? ONEK : TWOK);
    return verbosity;
  endfunction

endclass

int unit_default_data;

function int unit_get_data();
  return unit_default_data * 2;
endfunction

class ClsNew;
  localparam int OFFSET = 1;
  static string type_name = "ClsNew";
  string m_name;
  int m_data;
  int m_data2;
  function new(string name = ClsNew::type_name, int data = unit_default_data + OFFSET,
               int data2 = get_offset() + unit_get_data());
    m_name = name;
    m_data = data;
    m_data2 = data2;
  endfunction
  static function int get_offset();
    return 100;
  endfunction
endclass

class ClsNewExtern;
  const static string type_name = "ClsNewExtern";
  string m_name;
  extern function new(string name = type_name);
endclass

function ClsNewExtern::new(string name = type_name);
  m_name = name;
endfunction

class ClsNewDerived extends ClsNew;
  static string type_name = "ClsNewDerived";
  function new(string name = type_name);
    super.new(.data2(5));
    m_name = {m_name, ":", name};
  endfunction
endclass

module t;

  function int mod_trigger(int data = mod_data());
    return data;
  endfunction

  task mod_triggert(output int o, input int data = mod_data());
    o = data;
  endtask

  int mod_default_data;
  function int mod_data();
    return mod_default_data;
  endfunction

  int v;

  initial begin
    begin
      mod_triggert(v, 1234);
      `checkd(v, 1234);

      mod_default_data = 42;
      v = mod_trigger();
      `checkd(v, 42);
      v = mod_trigger(11);
      `checkd(v, 11);
      mod_default_data = 43;
      v = mod_trigger();
      `checkd(v, 43);
      v = mod_trigger();  // Multiple to test look up of duplicates
      `checkd(v, 43);

      mod_default_data = 52;
      mod_triggert(v);
      `checkd(v, 52);
      mod_triggert(v);  // Multiple to test look up of duplicates
      `checkd(v, 52);
    end
    begin
      Cls c = new;

      c.m_default_data = 42;
      v = c.trigger();
      `checkd(v, 42);
      v = c.trigger(11);
      `checkd(v, 11);
      c.m_default_data = 43;
      v = c.trigger();
      `checkd(v, 43);
      v = c.trigger();  // Multiple to test look up of duplicates
      `checkd(v, 43);
      v = c.trigger();  // Multiple to test look up of duplicates
      `checkd(v, 43);

      c.m_default_data = 52;
      c.triggert(v);
      `checkd(v, 52);
      c.triggert(v);  // Multiple to test look up of duplicates
      `checkd(v, 52);

      v = c.uvm_report(1);
      `checkd(v, 1000);
      v = c.uvm_report(2);
      `checkd(v, 2000);
      v = c.uvm_report(1, 111);
      `checkd(v, 111);
      v = c.uvm_report(1, 222);
      `checkd(v, 222);
    end

    begin
      ClsNew cn;
      ClsNewExtern cx;
      ClsNewDerived cd;

      unit_default_data = 10;
      cn = new;
      `checks(cn.m_name, "ClsNew");
      `checkd(cn.m_data, 11);
      `checkd(cn.m_data2, 120);
      ClsNew::type_name = "Renamed";
      unit_default_data = 20;
      cn = new();
      `checks(cn.m_name, "Renamed");
      `checkd(cn.m_data, 21);
      `checkd(cn.m_data2, 140);
      cn = new("given", 3);
      `checks(cn.m_name, "given");
      `checkd(cn.m_data, 3);

      cx = new;
      `checks(cx.m_name, "ClsNewExtern");

      cd = new;
      `checks(cd.m_name, "Renamed:ClsNewDerived");
      `checkd(cd.m_data, 21);
      `checkd(cd.m_data2, 5);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
