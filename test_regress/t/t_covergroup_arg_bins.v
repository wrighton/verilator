// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Bin values of covergroup arguments and instance constants, known when an instance is
// constructed (IEEE 1800-2023 19.5)

// verilog_format: off
`define stop $stop
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  const int OFFSET = 30;

  function automatic int twice(int n);
    return 2 * n;
  endfunction

  covergroup cg(int val, int lo, int hi) with function sample (int v, bit en);
    cp: coverpoint v {
      bins hit = {val};
      bins rng = {[lo : hi], 100};
      bins open = {[hi + 50 : $]};
      bins func = {twice(val)};
      bins global_const = {OFFSET};
      bins gated = {val + 2} iff (en);
      ignore_bins ign = {val + 1};
      illegal_bins ill = {[$ : -val]};
      bins others = default;
    }
    // Weightless, so the covergroup's coverage is cp's
    cp2: coverpoint v {
      option.weight = 0;
      bins a = {val};
      bins b = {[0 : 4]};
    }
    xx: cross cp, cp2{
      option.weight = 0;
      bins both = binsof (cp.hit) && binsof (cp2.a);
    }
  endgroup

  // An embedded covergroup's bins of an instance constant
  class Cls;
    const int m_lim;
    int m_value;
    covergroup cg_embedded;
      cp: coverpoint m_value {
        bins lo = {[0 : m_lim]};
        bins hi = {[m_lim + 1 : $]};
      }
    endgroup
    function new(int lim);
      m_lim = lim;
      cg_embedded = new;
    endfunction
  endclass

  cg inst;
  cg other;
  Cls obj;

  initial begin
    inst = new(5, 20, 22);
    inst.sample(5, 0);  // hit, cp2.a, xx.both
    inst.sample(6, 0);  // ign
    inst.sample(7, 0);  // none, as gated holds it but is not enabled
    inst.sample(21, 0);  // rng
    inst.sample(10, 0);  // func
    inst.sample(80, 0);  // open
    inst.sample(100, 0);  // rng, open
    inst.sample(3, 0);  // others, cp2.b
    inst.sample(30, 0);  // global_const
    `checkr(inst.get_inst_coverage(), 100.0 * (5.0 / 6));
    inst.sample(7, 1);  // gated
    `checkr(inst.get_inst_coverage(), 100.0);

    // Another instance has other bins
    other = new(1, 2, 3);
    other.sample(5, 0);  // others
    `checkr(other.get_inst_coverage(), 0.0);

    obj = new(4);
    obj.m_value = 3;
    obj.cg_embedded.sample();
    `checkr(obj.cg_embedded.get_inst_coverage(), 50.0);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
