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

  // Nor reading them in a force, whose value is read after the subroutine returns
  reg forced;
  bit static_bit;
  function automatic bit get_bit(bit x);
    return x;
  endfunction
  task static_arg(bit v);
    force forced = v;  // OK: argument of a static task is static
  endtask
  task automatic auto_arg(bit v);
    bit lv;
    force forced = v;  // Error: force reads an argument of an automatic task
    force forced = lv;  // Error: force reads an automatic
    force forced = get_bit(static_bit);  // OK: the call evaluates its own argument
  endtask
  task automatic ref_arg(ref bit v);
    force forced = v;  // Error: force reads a reference argument
  endtask
  task automatic cref_arg(const ref bit v);
    force forced = v;  // Error: force reads a constant reference argument
  endtask

  class ForceObj;
    bit m_prop;
  endclass
  task automatic ref_object(ref ForceObj r);
    force forced = r.m_prop;  // Error: a reference argument names the value
  endtask
  task automatic cref_object(const ref ForceObj r);
    force forced = r.m_prop;  // Error: a constant reference argument names the value
  endtask
  typedef struct {ForceObj obj; bit bits[2];} force_wrap_t;
  typedef struct {force_wrap_t inner;} force_outer_t;
  class ForceCls;
    bit m_prop;
    static ForceCls s_self;
    static ForceCls s_arr[2];
    static ForceCls s_queue[$];
    static ForceCls s_assoc[string];
    static ForceCls s_dyn[];
    static bit [31:0] s_vec;
    task drive();
      force forced = m_prop;  // OK: a property lasts as long as its object
      force forced = s_self.m_prop;  // OK: property read through a static handle
    endtask
    task write_prop();
      force m_prop = 1'b0;  // Error: only an NBA may update a non-static property
    endtask
    task auto_handle();
      automatic ForceCls lh = s_self;
      force forced = lh.m_prop;  // Error: an automatic handle names the value
    endtask
    task auto_handle_arg(ForceCls h);
      force forced = h.m_prop;  // Error: an automatic argument names the value
    endtask
    task auto_handle_array();
      automatic ForceCls la[2];
      force forced = la[0].m_prop;  // Error: an element of an automatic array of handles
    endtask
    task auto_index();
      automatic int which = 0;
      force forced = s_arr[which].m_prop;  // Error: an automatic index of a static array
    endtask
    task auto_index_queue();
      automatic int which = 0;
      force forced = s_queue[which].m_prop;  // Error: an automatic index of a queue
    endtask
    task auto_index_assoc();
      automatic string key = "a";
      force forced = s_assoc[key].m_prop;  // Error: an automatic key of an associative array
    endtask
    task auto_index_dyn();
      automatic int which = 0;
      force forced = s_dyn[which].m_prop;  // Error: an automatic index of a dynamic array
    endtask
    task auto_sel_bound();
      automatic int lo = 0;
      force forced = s_vec[lo];  // Error: an automatic index of a packed vector
    endtask
    task auto_struct();
      automatic force_wrap_t w;
      force forced = w.obj.m_prop;  // Error: an automatic struct holding the handle
    endtask
    task auto_struct_array();
      automatic force_wrap_t w;
      force forced = w.bits[0];  // Error: an automatic struct, array member
    endtask
    task auto_struct_nested();
      automatic force_outer_t o;
      force forced = o.inner.bits[1];  // Error: a nested member of an automatic struct
    endtask
  endclass

  // Nor reading automatic variables in the event control of a non-blocking assignment
  reg areg;
  task automatic ev_tsk;
    reg autom1;
    begin : ev_block
      reg autom2;
      areg <= @(autom1) 0;  // Error: automatic in non-blocking event control
      areg <= @(autom2) 0;  // Error: automatic in non-blocking event control
    end
  endtask

  class EvWaiter;
    event trigger;
    int m_val;
    task wait_member;
      int dly;
      areg <= #(dly) 0;  // OK: delay is not an event control
      @(m_val);  // OK: procedural event control on class member
      areg <= @(m_val) 0;  // OK: class member in non-blocking event control
      areg <= @trigger 0;  // OK: class event member in non-blocking event control
    endtask
    static task wait_trigger;
      EvWaiter waiter;
      waiter = new;
      @waiter.trigger;  // OK: procedural event control
      areg <= @waiter.trigger 0;  // OK: handle of a class property
    endtask
  endclass

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

  // A timed NBA is rejected as an automatic-argument write, not as a user-authored fork.
  task automatic timed_ref_nba(ref int arg);
    arg <= #1 5;
  endtask

endmodule
