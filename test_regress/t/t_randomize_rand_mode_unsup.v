// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Element;
  rand bit v;
endclass

class Packet;
  rand int m_dyn_arr[][];
  rand int m_unp_arr[10][2];
  rand int m_assoc[int];
  rand Element m_handles[2];
  rand Element m_dyn_handles[];
  rand Element m_q_handles[$];
  rand struct {int y;} m_struct;
  rand struct {int y;} m_struct_arr[];
  static rand int m_static_arr[];
  rand int m_queue[$];
  rand int m_wild[*];
  Packet m_objs[];
endclass

class Node;
  rand Node m_next;
  rand int m_arr[];
  constraint c {m_arr.size() < 4;}
  rand struct {rand Element h;} m_s;
  rand Element m_q_handles[$];
endclass

class Node;
  rand Node m_next;
  rand int m_arr[];
  constraint c {m_arr.size() < 4;}
endclass

module t;
  initial begin
    automatic Packet p = new;
    automatic Node n = new;
    p.m_dyn_arr[0][1].rand_mode(0);
    p.m_unp_arr[0][1].rand_mode(0);
    p.m_assoc[0].rand_mode(0);
    p.m_struct.y.rand_mode(0);
    p.m_struct_arr[0].rand_mode(0);
    p.m_static_arr[0].rand_mode(0);
    p.m_queue[$].rand_mode(0);
    p.m_wild[1].rand_mode(0);
    p.m_objs[0].rand_mode(0);
    n.m_arr[0].rand_mode(0);
    void'(n.randomize());
    // These select random variables, not all fields of the referenced object.
    p.m_handles[0].rand_mode(0);
    p.m_dyn_handles[0].rand_mode(0);
    p.m_s.h.rand_mode(0);
    p.m_q_handles[$].rand_mode(0);
    n.m_arr[0].rand_mode(0);
    void'(n.randomize());
  end
endmodule
