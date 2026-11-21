// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0


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


// Test case 3: rand class member declared in a base class of the randomized object
class inh_leaf;
  rand int m_w;
  constraint c_w {m_w inside {[20 : 22]};}
endclass

class inh_inner;
  rand int m_v;
  rand inh_leaf m_leaf;
  constraint c_v {m_v inside {[10 : 12]};}
  function new;
    m_leaf = new;
  endfunction
endclass

class inh_base;
  rand inh_inner m_in;
  rand int m_x;
  function new;
    m_in = new;
  endfunction
endclass

class inh_derived extends inh_base;
  rand int m_y;
  constraint c_y {m_y inside {[1 : 3]};}
endclass

class inh_derived2 extends inh_derived;
endclass

class inh_caller;
  int m_x = 7;
  function void run(inh_derived2 d);
    int ok;
    ok = d.randomize() with {m_x == local::m_x;};
    if (ok != 1) $stop;
    if (d.m_x != 7) $stop;
    if (!(d.m_in.m_v inside {[10 : 12]})) $stop;
    if (!(d.m_in.m_leaf.m_w inside {[20 : 22]})) $stop;
  endfunction
endclass


module t_constraint_global_nested_member;
  initial begin
    tb_test tb;
    axi_wrap_test axi_t;
    inh_derived inh_d;
    inh_derived2 inh_d2;
    inh_caller inh_c;

    tb = new;
    tb.run_phase(0);

    axi_t = new();
    axi_t.build_phase();

    inh_d = new;
    inh_d2 = new;
    inh_c = new;
    repeat (4) begin
      if (inh_d.randomize() != 1) $stop;
      if (!(inh_d.m_in.m_v inside {[10 : 12]})) $stop;
      if (!(inh_d.m_in.m_leaf.m_w inside {[20 : 22]})) $stop;
      if (!(inh_d.m_y inside {[1 : 3]})) $stop;
      inh_c.run(inh_d2);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
