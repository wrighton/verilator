// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Element;
  rand bit v;
endclass

class Packet;
  rand int m_dyn_arr[];
  rand int m_unp_arr[10];
  rand Element m_handles[2];
  rand Element m_dyn_handles[];
  rand Element m_q_handles[$];
  rand struct {int y;} m_struct;
  rand struct {rand Element h;} m_s;

  task check_elements;
    m_handles[0].rand_mode(0);
    m_dyn_handles[0].rand_mode(0);
  endtask
endclass

module t;
  initial begin
    automatic Packet p = new;
    p.m_dyn_arr[0].rand_mode(0);
    p.m_unp_arr[0].rand_mode(0);
    p.m_struct.y.rand_mode(0);
    // These select random variables, not all fields of the referenced object.
    p.m_handles[0].rand_mode(0);
    p.m_dyn_handles[0].rand_mode(0);
    p.m_s.h.rand_mode(0);
    p.m_q_handles[$].rand_mode(0);
    p.check_elements();
  end
endmodule
