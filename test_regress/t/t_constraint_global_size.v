// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Size constraints on arrays of rand member objects are solved with the outer
// object (IEEE 1800-2023 18.5.8), and the arrays resized

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(cond) do if (!(cond)) begin $write("%%Error: %s:%0d:  check failed\n", `__FILE__,`__LINE__); `stop; end while(0);
// verilog_format: on

class Inner;
  rand bit [7:0] m_d[];
  rand bit [7:0] m_q[$];
  constraint c_size { m_d.size() inside {[1:2]}; m_q.size() == 8; }
endclass

// Element constraints need the sizes solved before the elements
class InnerElem;
  rand bit [7:0] m_e[];
  constraint c_e { m_e.size() inside {[2:4]}; foreach (m_e[i]) m_e[i] == 8'(i + 1); }
endclass

typedef class PlainElem;

class InnerBase;
  rand bit [7:0] m_b[$];
  constraint c_b { m_b.size() == 5; }
endclass

class InnerDerived extends InnerBase;
  rand int m_y;
endclass

// No constraints of its own
class Plain;
  rand bit [3:0] m_p[$];
endclass

class InnerAssoc;
  rand int m_aa[int];
endclass

class Mid;
  rand Inner m_inner;
  function new;
    m_inner = new;
  endfunction
endclass

class Outer;
  rand Inner m_in;
  rand Inner m_in2;
  rand Mid m_mid;
  rand InnerElem m_ie;
  rand InnerDerived m_id;
  rand Plain m_pa;
  rand Plain m_pb;
  rand PlainElem m_pe;
  rand InnerAssoc m_ia;
  rand int m_x;
  rand int m_n;
  constraint c_x { m_x == m_in.m_d.size() + 10; }
  constraint c_p {
    m_n inside {[1:4]};
    m_pa.m_p.size() == m_n;
    m_pb.m_p.size() == m_n + 1;
    foreach (m_pa.m_p[i]) m_pa.m_p[i] == 4'(i + 7);
    m_pe.m_p.size() == 3;
  }
  // The size of an associative array is a state value
  constraint c_aa { m_ia.m_aa.size() == 2; }
  function new;
    m_in = new;
    m_in2 = new;
    m_mid = new;
    m_ie = new;
    m_id = new;
    m_pa = new;
    m_pb = new;
    m_pe = new;
    m_ia = new;
    m_ia.m_aa[1] = 1;
    m_ia.m_aa[5] = 5;
  endfunction
endclass

// Elements constrained here, size only by Outer
class PlainElem;
  rand bit [3:0] m_p[$];
  constraint c_e { foreach (m_p[i]) m_p[i] < 5; }
endclass

// Constraints inherited from the class owning the member
class OuterPlain;
  rand Plain m_pa;
  rand int m_n;
  constraint c {
    m_n inside {[1:4]};
    m_pa.m_p.size() == m_n;
    foreach (m_pa.m_p[i]) m_pa.m_p[i] == 4'(i + 7);
  }
  function new;
    m_pa = new;
  endfunction
endclass

class OuterPlainDerived extends OuterPlain;
  rand int m_z;
endclass

// The own array has an element constraint, so sizes are solved first
class Holder;
  rand Plain m_s;
  Plain m_cfg;
  rand bit [3:0] m_own[$];
  rand int m_x;
  constraint c { m_own.size() == 2; foreach (m_own[i]) m_own[i] != 0; }
  function new;
    m_s = new;
    m_cfg = new;
  endfunction
endclass

module t;
  initial begin
    automatic Outer o = new;
    automatic Inner in = new;
    automatic PlainElem pe = new;
    automatic OuterPlain op = new;
    automatic OuterPlainDerived opd = new;
    automatic Holder h = new;
    automatic Plain other = new;
    automatic int nonzero = 0;
    automatic int randomize_result;

    repeat (5) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkr(o.m_in.m_d.size() inside {[1:2]});
      `checkd(o.m_in.m_q.size(), 8);
      `checkd(o.m_x, o.m_in.m_d.size() + 10);
      `checkr(o.m_in2.m_d.size() inside {[1:2]});
      `checkd(o.m_in2.m_q.size(), 8);
      `checkr(o.m_mid.m_inner.m_d.size() inside {[1:2]});
      `checkd(o.m_mid.m_inner.m_q.size(), 8);
      `checkr(o.m_ie.m_e.size() inside {[2:4]});
      foreach (o.m_ie.m_e[i]) `checkd(o.m_ie.m_e[i], 8'(i + 1));
      `checkd(o.m_id.m_b.size(), 5);
      `checkr(o.m_n inside {[1:4]});
      `checkd(o.m_pa.m_p.size(), o.m_n);
      `checkd(o.m_pb.m_p.size(), o.m_n + 1);
      foreach (o.m_pa.m_p[i]) `checkd(o.m_pa.m_p[i], 4'(i + 7));
      `checkd(o.m_pe.m_p.size(), 3);
      foreach (o.m_pe.m_p[i]) `checkr(o.m_pe.m_p[i] < 5);
      // Elements added by the resize are randomized
      foreach (o.m_in.m_q[i]) if (o.m_in.m_q[i] != 0) nonzero++;
    end
    `checkr(nonzero > 20);

    // The member object can still be randomized directly
    repeat (3) begin
      randomize_result = in.randomize();
      `checkd(randomize_result, 1);
      `checkr(in.m_d.size() inside {[1:2]});
      `checkd(in.m_q.size(), 8);
    end

    // A class sized only through a member object keeps its size when randomized directly
    pe.m_p = '{1, 2};
    randomize_result = pe.randomize();
    `checkd(randomize_result, 1);
    `checkd(pe.m_p.size(), 2);
    `checkr(pe.m_p[1] < 5);

    repeat (3) begin
      randomize_result = op.randomize();
      `checkd(randomize_result, 1);
      `checkd(op.m_pa.m_p.size(), op.m_n);
      foreach (op.m_pa.m_p[i]) `checkd(op.m_pa.m_p[i], 4'(i + 7));
      randomize_result = opd.randomize();
      `checkd(randomize_result, 1);
      `checkd(opd.m_pa.m_p.size(), opd.m_n);
      foreach (opd.m_pa.m_p[i]) `checkd(opd.m_pa.m_p[i], 4'(i + 7));
    end

    // The size of a member associative array is not randomized
    o.m_ia.m_aa.delete(5);
    randomize_result = o.randomize();
    `checkd(randomize_result, 0);
    `checkd(o.m_ia.m_aa.size(), 1);
    o.m_ia.m_aa[7] = 7;

    // randomize() with, sizing through the class constraints and the with-block
    repeat (3) begin
      randomize_result = o.randomize() with { m_in.m_d.size() == 2; };
      `checkd(randomize_result, 1);
      `checkd(o.m_in.m_d.size(), 2);
      `checkd(o.m_x, 12);
      `checkr(o.m_ie.m_e.size() inside {[2:4]});
      foreach (o.m_ie.m_e[i]) `checkd(o.m_ie.m_e[i], 8'(i + 1));
      randomize_result = o.randomize() with {
        m_pa.m_p.size() == 4;
        foreach (m_pb.m_p[i]) m_pb.m_p[i] == 3;
      };
      `checkd(randomize_result, 1);
      `checkd(o.m_pa.m_p.size(), 4);
      `checkd(o.m_pb.m_p.size(), 5);
      foreach (o.m_pb.m_p[i]) `checkd(o.m_pb.m_p[i], 4'd3);
    end

    // An array of a held object sized only by the with-block; new elements are randomized
    nonzero = 0;
    repeat (5) begin
      h.m_s.m_p.delete();
      randomize_result = h.randomize() with {
        m_s.m_p.size() inside {[1:4]};
        m_x == m_s.m_p.size();
      };
      `checkd(randomize_result, 1);
      `checkd(h.m_x, h.m_s.m_p.size());
      foreach (h.m_s.m_p[i]) if (h.m_s.m_p[i] != 0) nonzero++;
    end
    `checkr(nonzero > 0);
    // The size of an array of an object not randomized is a state value
    h.m_cfg.m_p = '{1, 2, 3};
    randomize_result = h.randomize() with { m_x == m_cfg.m_p.size(); };
    `checkd(randomize_result, 1);
    `checkd(h.m_x, 3);
    `checkd(h.m_cfg.m_p.size(), 3);
    other.m_p = '{1};
    randomize_result = h.randomize() with { m_x == other.m_p.size(); };
    `checkd(randomize_result, 1);
    `checkd(h.m_x, 1);
    `checkd(other.m_p.size(), 1);
    h.m_s.m_p.rand_mode(0);
    h.m_s.m_p = '{1, 2};
    randomize_result = h.randomize() with { m_s.m_p.size() == 3; };
    `checkd(randomize_result, 0);
    `checkd(h.m_s.m_p.size(), 2);

    // rand_mode(0) keeps the size of a member object array
    o.m_ie.m_e = '{1, 2, 3};
    o.m_ie.m_e.rand_mode(0);
    randomize_result = o.randomize();
    `checkd(randomize_result, 1);
    `checkd(o.m_ie.m_e.size(), 3);
    o.m_ie.m_e = '{1};
    randomize_result = o.randomize();
    `checkd(randomize_result, 0);
    `checkd(o.m_ie.m_e.size(), 1);
    o.m_ie.m_e.rand_mode(1);

    o.m_in.m_d = '{1, 2, 3};
    o.m_in.m_d.rand_mode(0);
    randomize_result = o.randomize();
    `checkd(randomize_result, 0);
    `checkd(o.m_in.m_d.size(), 3);
    o.m_in.m_d = '{4, 5};
    randomize_result = o.randomize();
    `checkd(randomize_result, 1);
    `checkd(o.m_in.m_d.size(), 2);
    `checkd(o.m_in.m_d[0], 8'd4);
    `checkd(o.m_x, 12);
    o.m_in.m_d.rand_mode(1);
    randomize_result = o.randomize();
    `checkd(randomize_result, 1);
    `checkr(o.m_in.m_d.size() inside {[1:2]});

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
