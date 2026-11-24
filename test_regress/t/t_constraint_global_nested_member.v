// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Test: constraints of a rand class member that a nested rand member inherits
class inh_leaf;
  rand bit [7:0] v;
  constraint c_v {v == 5;}
endclass

class inh_base;
  rand inh_leaf leaf = new;
endclass

class inh_member extends inh_base;
endclass

class inh_holder;
  rand inh_member m = new;
endclass

// Test: a rand class member hiding an inherited one of its name, with a constraint of the same
// name or another
class hide_leaf;
  rand bit [6:0] v;
  constraint c {v == 5;}
endclass

class hide_same_leaf;
  rand bit [6:0] v;
  constraint c {v == 7;}
endclass

class hide_other_leaf;
  rand bit [6:0] v;
  constraint c_other {v == 7;}
endclass

class hide_base;
  rand hide_leaf leaf = new;
endclass

class hide_same extends hide_base;
  rand hide_same_leaf leaf = new;
endclass

class hide_other extends hide_base;
  rand hide_other_leaf leaf = new;
endclass

class hide_holder;
  rand hide_same same = new;
  rand hide_other other = new;
endclass


// Test case 1
class uvm_reg_field;
  rand int m_value;
endclass

class reg_class;
  rand int m_value;
  rand uvm_reg_field _dummy;
  constraint _dummy_is_reg {_dummy.m_value == m_value;}
  function new();
    _dummy = new;
  endfunction
endclass

class block_class;
  rand reg_class m_r;
  function new();
    m_r = new;
  endfunction
endclass

class tb_test;
  virtual task run_phase(int phase);
    block_class regmodel;
    regmodel = new;
    // verilator lint_off IGNOREDRETURN
    void'(regmodel.randomize() with {m_r.m_value == 32'hA5;});
    // verilator lint_on IGNOREDRETURN
    if (regmodel.m_r.m_value != 32'hA5) $stop;
  endtask
endclass


// Test case 2
class axi_agent_config;
   rand bit r_ready_delays;
   constraint r_ready_delays_c {
      r_ready_delays == 0;
   }
endclass

class axi_env_config;
   rand axi_agent_config   axim_agt_cfg;
   function new();
      axim_agt_cfg = new;
   endfunction
endclass

class axi_base_test;
  axi_env_config axi_env_cfg;
  virtual function void build_phase();
    configure_axi_env();
  endfunction
  function void configure_axi_env();
    axi_env_cfg = new;
  endfunction
endclass

class axi_wrap_test extends axi_base_test;
  function void configure_axi_env();
    void'(axi_env_cfg.randomize());
  endfunction
endclass


module t_constraint_global_nested_member;
  initial begin
    tb_test tb;
    axi_wrap_test axi_t;

    tb = new;
    tb.run_phase(0);
    begin
      automatic inh_holder h = new;
      automatic hide_holder hh = new;
      automatic int ok;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.m.leaf.v, 5);
      repeat (10) begin
        ok = hh.randomize();
        `checkd(ok, 1);
        `checkd(hh.same.leaf.v, 7);
        `checkd(hh.other.leaf.v, 7);
      end
    end

    axi_t = new();
    axi_t.build_phase();

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
