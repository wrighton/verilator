// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 by Wilson Snyder and Contributors
// SPDX-License-Identifier: CC0-1.0

class Cls;
  rand int m_d[3][];
  rand int m_dd[][];
  rand int m_ad[int][];
  rand int m_q[$][2];
  rand int m_b;
  function new();
    foreach (m_d[i]) m_d[i] = new[i + 1];
    m_dd = new[3];
    foreach (m_dd[i]) m_dd[i] = new[2];
    m_ad[1] = new[2];
    m_q = '{'{0, 0}, '{0, 0}};
  endfunction
  // All elements are 0 before randomization, so the constraints hold as state
  constraint c_idx {
    m_b inside {[0 : 2]};
    m_d[m_b].sum() with (item) == 0;
    m_d[m_b].sum() == 0;
    m_dd[m_b].sum() with (item) == 0;
    m_dd[1].sum() with (item) == 0;
    m_ad[1].sum() with (item) == 0;
    m_q[1].sum() with (item) == 0;
  }
endclass

module t;
  initial begin
    Cls c;
    int ok;
    c = new;
    ok = c.randomize();
    if (ok != 1) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
