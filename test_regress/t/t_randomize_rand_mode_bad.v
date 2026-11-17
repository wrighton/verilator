// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Packet;
  int m_val;
  rand int m_other_val;
  rand logic [7:0] m_pack;
  Packet m_handles[2];

  task check_invalid_receivers;
    m_val.rand_mode(0);
    m_handles[0].m_val.rand_mode(0);
  endtask

  function Packet get_element;
    return m_handles[0];
  endfunction

  function int get_rand_mode;
    return rand_mode();
  endfunction
endclass

module t;
  Packet p;

  initial begin
    p = new;
    p.check_invalid_receivers();
    p.m_val.rand_mode(0);
    p.m_pack[0].rand_mode(0);
    $display("p.rand_mode()=%0d", p.rand_mode());
    $display(p.rand_mode(0));
    p.m_other_val.rand_mode();
    p.m_val = p.m_handles[0].rand_mode();
    p.m_val = p.get_element().rand_mode();
    p.m_val = p.m_handles[0].rand_mode(0);
  end
endmodule
