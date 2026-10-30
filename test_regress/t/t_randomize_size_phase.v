// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Sizes solved in a first phase stay fixed in the final solve, and solved
// values are kept

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// m_q2 has an element constraint, so the sizes are solved in a separate phase
class Sizes;
  rand bit [3:0] m_q1[$];
  rand bit [3:0] m_q2[$];
  rand int m_x;
  constraint c {
    m_q1.size() inside {[1:8]};
    m_q2.size() == 2;
    foreach (m_q2[i]) m_q2[i] == 4'(i + 1);
    m_x == m_q1.size();
  }
endclass

class DerivedSizes extends Sizes;
  rand int m_y;
endclass

class Scalar;
  rand int m_v;
endclass

// m_s.m_v is left to the basic randomization of Scalar, which must not override it
class Leaf;
  rand Scalar m_s;
  rand bit [7:0] m_p[];
  constraint c { m_s.m_v == 5; m_p.size() == 2; foreach (m_p[i]) m_p[i] == 8'(i + 1); }
  function new;
    m_s = new;
  endfunction
endclass

module t;
  initial begin
    automatic Sizes s = new;
    automatic DerivedSizes d = new;
    automatic Leaf l = new;
    automatic int randomize_result;

    repeat (10) begin
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      `checkd(s.m_x, s.m_q1.size());
      `checkd(s.m_q2.size(), 2);
      `checkd(s.m_q2[1], 4'd2);
      randomize_result = d.randomize();
      `checkd(randomize_result, 1);
      `checkd(d.m_x, d.m_q1.size());
      `checkd(d.m_q2[1], 4'd2);
    end

    repeat (3) begin
      randomize_result = l.randomize();
      `checkd(randomize_result, 1);
      `checkd(l.m_s.m_v, 5);
      `checkd(l.m_p.size(), 2);
      `checkd(l.m_p[1], 8'd2);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
