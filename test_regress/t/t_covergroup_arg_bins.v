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

  // Arrays of a bin for each value, once each, named by value (IEEE 1800-2023 19.5)
  covergroup cg_array(int lo, int hi) with function sample (int v, bit w, bit [64:0] wide);
    cp: coverpoint v {
      bins arr[] = {[lo : hi], hi + 5, lo};
      ignore_bins ign = {lo + 1};
    }
    // Of --coverage-max-bins 16: 16 values are kept, 17 ignored
    cp_max: coverpoint v {
      bins max[] = {[lo : lo + 15]};
    }
    cp_big: coverpoint v {
      bins big[] = {[lo : lo + 16]};
    }
    // An ignore array, which excludes its values from the bins of an array
    cp_ign: coverpoint v {
      bins all[] = {[lo : hi]};
      ignore_bins ign[] = {lo, hi};
    }
    // Values wider than 64 bits
    cp_wide: coverpoint wide {
      bins warr[] = {[{1'b1, 64'(lo)} : {1'b1, 64'(hi)}]};
    }
    cw: coverpoint w;
    x: cross cp, cw{
      bins top = binsof (cp.arr) intersect {9};
    }
  endgroup

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
    inst.sample(0, 0);  // others, cp2.b, but not ill, which is below -val
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

    begin
      automatic cg_array arr_inst = new(2, 4);  // arr[2], arr[4], and arr[9]; 3 is ignored
      automatic cg_array arr_other = new(10, 12);  // arr[10], arr[12], and arr[17]
      arr_inst.sample(2, 0, {1'b1, 64'd3});
      arr_inst.sample(9, 1, 0);
      arr_inst.sample(4, 1, 0);
      `checkr(arr_inst.cp.get_inst_coverage(), 100.0);
      `checkr(arr_inst.cp_wide.get_inst_coverage(), 100.0 / 3);
      // top, and the 4 automatic bins of arr[2] and arr[4]
      `checkr(arr_inst.x.get_inst_coverage(), 100.0 * (3.0 / 5));
      `checkr(arr_inst.cp_max.get_inst_coverage(), 100.0 * (3.0 / 16));
      `checkr(arr_inst.cp_ign.get_inst_coverage(), 0.0);  // only all[3], of 3, is a bin
      arr_inst.sample(3, 0, 0);
      `checkr(arr_inst.cp_ign.get_inst_coverage(), 100.0);
      arr_other.sample(12, 0, 0);
      `checkr(arr_other.cp.get_inst_coverage(), 100.0 / 3);
    end
    begin
      automatic cg_array arr_neg = new(-3, -1);  // arr[-3], arr[-1], and arr[4]
      arr_neg.sample(-3, 0, 0);
      arr_neg.sample(-2, 0, 0);
      `checkr(arr_neg.cp.get_inst_coverage(), 100.0 / 3);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
