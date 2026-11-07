// DESCRIPTION: Verilator: Verilog Test module for SystemVerilog 'alias'
//
// Simple bi-directional alias test.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkq(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%p exp=%p\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  // Nested 'with' clauses, where an inner one uses an outer one's argument; each argument has
  // the type of its own array, here narrower in the inner array (IEEE 1800-2023 7.12)
  task automatic check_nested_with();
    bit [63:0] crc = 64'h5aef0c8d_d70a4497;
    int fa[3];
    shortint dd[] = new[3];
    byte dq[$] = {0, 0, 0, 0};
    int am[bit [39:0]];
    int fq[$];
    int key[3];
    int exp, got, lim;
    int expi[$], expv[$], gotq[$];
    for (int iter = 0; iter < 20; ++iter) begin
      crc = {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
      foreach (fa[i]) fa[i] = int'(crc[i*16+:16]) * 1009;
      foreach (dd[i]) dd[i] = crc[i*13+:16];
      foreach (dq[i]) dq[i] = crc[i*9+:8];
      am.delete();
      foreach (fa[i]) am[{8'(i + 1), crc[i*7+:32]}] = fa[i];

      // Reductions, renamed and default 'item' arguments at each level
      exp = 0;
      foreach (fa[i]) foreach (dq[j]) exp += fa[i] + int'(dq[j]);
      got = fa.sum(x) with (dq.sum(y) with (x + int'(y)));
      `checkd(got, exp);
      exp = 0;
      foreach (fa[i]) foreach (dq[j]) exp += fa[i] ^ int'(dq[j]);
      got = fa.sum with (dq.sum(y) with (item ^ int'(y)));
      `checkd(got, exp);
      exp = 0;
      foreach (fa[i]) foreach (dq[j]) exp += fa[i] - int'(dq[j]);
      got = fa.sum(x) with (dq.sum with (x - int'(item)));
      `checkd(got, exp);
      // Same name at both levels: the inner argument hides the outer one
      exp = 0;
      foreach (fa[i]) begin
        exp += fa[i];
        foreach (dq[j]) exp += int'(dq[j]);
      end
      got = fa.sum(x) with (x + dq.sum(x) with (int'(x)));
      `checkd(got, exp);
      exp = 1;
      foreach (fa[i]) foreach (dd[j]) exp *= fa[i] + int'(dd[j]);
      got = fa.product(x) with (dd.product(y) with (x + int'(y)));
      `checkd(got, exp);
      exp = '1;
      foreach (fa[i]) foreach (dd[j]) exp &= fa[i] | int'(dd[j]);
      got = fa.and(x) with (dd.and(y) with (x | int'(y)));
      `checkd(got, exp);
      exp = 0;
      foreach (fa[i]) foreach (dq[j]) exp |= fa[i] & ~int'(dq[j]);
      got = fa.or(x) with (dq.or(y) with (x & ~int'(y)));
      `checkd(got, exp);
      exp = 0;
      foreach (am[k]) foreach (dq[j]) exp ^= am[k] + int'(dq[j]);
      got = am.xor(x) with (dq.xor(y) with (x + int'(y)));
      `checkd(got, exp);
      // Inner array wider than the outer one
      exp = 0;
      foreach (dq[i]) foreach (fa[j]) exp += int'(dq[i]) * fa[j];
      got = dq.sum(x) with (fa.sum(y) with (int'(x) * y));
      `checkd(got, exp);

      // Locators, min, max and unique; the keys differ, so 'key > lim' holds for 1 or 2 of them
      foreach (fa[i]) begin
        key[i] = 0;
        foreach (dq[j]) key[i] += fa[i] + int'(dq[j]);
      end
      lim = (key[0] + key[1] + key[2]) / 3;
      expi = {};
      expv = {};
      foreach (fa[i]) begin
        if (key[i] > lim) begin
          expi.push_back(i);
          expv.push_back(fa[i]);
        end
      end
      gotq = fa.find(x) with (dq.sum(y) with (x + int'(y)) > lim);
      `checkq(gotq, expv);
      gotq = fa.find_index(x) with (dq.sum(y) with (x + int'(y)) > lim);
      `checkq(gotq, expi);
      gotq = fa.find_first(x) with (dq.sum(y) with (x + int'(y)) > lim);
      `checkq(gotq, expv[0:0]);
      gotq = fa.find_first_index(x) with (dq.sum(y) with (x + int'(y)) > lim);
      `checkq(gotq, expi[0:0]);
      gotq = fa.find_last(x) with (dq.sum(y) with (x + int'(y)) > lim);
      `checkq(gotq, expv[$:$]);
      gotq = fa.find_last_index(x) with (dq.sum(y) with (x + int'(y)) > lim);
      `checkq(gotq, expi[$:$]);
      // One element for each of the two 'with' values, in either order
      gotq = fa.unique_index(x) with (dq.sum(y) with (x + int'(y)) > lim);
      `checkd(gotq.size(), 2);
      `checkd((key[gotq[0]] > lim) ^ (key[gotq[1]] > lim), 1'b1);
      gotq = fa.unique(x) with (dq.sum(y) with (x + int'(y)) > lim);
      `checkd(gotq.size(), 2);
      exp = key[0] - fa[0] * 4;  // Sum of dq
      `checkd(gotq[0] inside {fa} && gotq[1] inside {fa}, 1'b1);
      `checkd((gotq[0] * 4 + exp > lim) ^ (gotq[1] * 4 + exp > lim), 1'b1);
      exp = 0;
      foreach (fa[i]) if (key[i] < key[exp]) exp = i;
      gotq = fa.min(x) with (dq.sum(y) with (x + int'(y)));
      `checkd(gotq.size(), 1);
      `checkd(gotq[0], fa[exp]);
      exp = 0;
      foreach (fa[i]) if (key[i] > key[exp]) exp = i;
      gotq = fa.max(x) with (dq.sum(y) with (x + int'(y)));
      `checkd(gotq.size(), 1);
      `checkd(gotq[0], fa[exp]);
      // A locator in an inner 'with'
      expv = {};
      foreach (fa[i]) begin
        exp = 0;
        foreach (dd[j]) if (fa[i] / 1009 > int'(dd[j])) ++exp;
        if (exp >= 2) expv.push_back(fa[i]);
      end
      gotq = fa.find(x) with (dd.find(y) with (x / 1009 > int'(y)).size() >= 2);
      `checkq(gotq, expv);

      // sort and rsort order by the 'with' value
      fq = {fa[0], fa[1], fa[2]};
      fq.sort(x) with (dq.sum(y) with (x + int'(y)));
      for (int i = 1; i < 3; ++i) `checkd(fq[i-1] <= fq[i], 1);
      fq.rsort(x) with (dq.sum(y) with (x - int'(y)));
      for (int i = 1; i < 3; ++i) `checkd(fq[i-1] >= fq[i], 1);

      // item.index of the outer argument in an inner 'with'
      expv = {};
      foreach (am[k]) begin
        exp = 0;
        foreach (dq[j]) exp += int'(k >> 32) * int'(dq[j]);
        if (exp > 0) expv.push_back(am[k]);
      end
      gotq = am.find(x) with (dq.sum(y) with (int'(x.index >> 32) * int'(y)) > 0);
      `checkq(gotq, expv);
      expi = {};
      foreach (dd[i]) if (int'(dq[i+1]) < int'(dd[i])) expi.push_back(i);
      gotq = dd.find_index(x) with (dq.find_first_index(y) with (y.index == x.index + 1
                                                                && int'(y) < int'(x)).size() > 0);
      `checkq(gotq, expi);
    end
  endtask

  initial begin
    automatic int tofind;
    automatic int aliases[$];
    automatic int found[$];
    automatic int i;
    automatic byte byteq[$] = {2, -1, 127};
    automatic byte b[];
    automatic logic [7:0] m[2][2];
    automatic logic bit_arr[1024];

    aliases = '{1, 4, 6, 8};
    tofind = 6;
    found = aliases.find with (item == 1);
    `checkh(found.size, 1);
    found = aliases.find(j) with (j == tofind);
    `checkh(found.size, 1);
    // And as function
    aliases.find(i) with (i == tofind);

    // No parenthesis
    tofind = 0;
    found = aliases.find with (item == tofind);
    `checkh(found.size, 0);
    aliases.find with (item == tofind);

    // bug3387
    i = aliases.sum();
    `checkh(i, 'h13);
    i = byteq.sum() with (int'(item));
    `checkh(i, 128);

    // Unique (array method)
    tofind = 4;
    found = aliases.find with (tofind);  // "true" match
    `checkh(found.size, 4);
    found = aliases.find() with (item == tofind);
    `checkh(found.size, 1);
    found = aliases.find(i) with (i == tofind);
    `checkh(found.size, 1);
    i = aliases.or(v) with (v);
    `checkh(i, 'hf);
    i = aliases.and(v) with (v);
    `checkh(i, 0);
    i = aliases.xor(v) with (v);
    `checkh(i, 'hb);

    // Based roughly on IEEE 1800-2023 7.12.3
    // verilator lint_off WIDTHEXPAND
    b = {1, 2, 3, 4};
    i = b.sum;  // = 10 <= 1 + 2 + 3 + 4
    `checkd(i, 10);

    i = b.product;  // = 24 <= 1 * 2 * 3 * 4
    `checkd(i, 24);

    i = b.xor with (item + 4);  // = 12 <= 5 ^ 6 ^ 7 ^ 8
    `checkd(i, 12);

    m = '{'{5, 10}, '{15, 20}};
    i = m.sum with (item.sum with (item));  // = 50 <= 5+10+15+20
    `checkd(i, 50);

    // Width of the reduction method's result is the dtype of the with's expression
    // verilator lint_on WIDTHEXPAND
    for (i = 0; i < 1024; ++i) bit_arr[i] = 1'b1;
    i = bit_arr.sum with (int'(item));  // forces result to be 32-bit
    `checkd(i, 1024);

    check_nested_with();

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
