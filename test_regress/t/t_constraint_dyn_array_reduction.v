// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Test dynamic array reduction methods (xor, sum, and, or, product)
// without 'with' clause in constraints.
// Each method is tested in a separate class to avoid conflicting constraints.
// SizedTest and CondTest reduce (and use 'inside' on) dynamic arrays and queues
// whose size is solved in the same randomize() call.

module t;

  class XorTest;
    rand bit [7:0] data[];
    rand bit [7:0] result;
    function new();
      data = new[4];
    endfunction
    constraint c_size {data.size() == 4;}
    constraint c_xor {result == data.xor();}
  endclass

  class SumTest;
    rand bit [7:0] data[];
    rand bit [7:0] result;
    function new();
      data = new[4];
    endfunction
    constraint c_size {data.size() == 4;}
    constraint c_sum {result == data.sum();}
  endclass

  class AndTest;
    rand bit [7:0] data[];
    rand bit [7:0] result;
    function new();
      data = new[4];
    endfunction
    constraint c_size {data.size() == 4;}
    constraint c_and {result == data.and();}
  endclass

  class OrTest;
    rand bit [7:0] data[];
    rand bit [7:0] result;
    function new();
      data = new[4];
    endfunction
    constraint c_size {data.size() == 4;}
    constraint c_or {result == data.or();}
  endclass

  class ProductTest;
    rand bit [7:0] data[];
    rand bit [7:0] result;
    function new();
      data = new[4];
    endfunction
    constraint c_size {data.size() == 4;}
    constraint c_prod {result == data.product();}
  endclass

  class SizedTest;
    rand int n;
    rand bit [2:0] dsum[];
    rand bit [2:0] qsum[$];
    rand bit [2:0] qprod[$];
    rand bit [2:0] dand[];
    rand bit [2:0] qor[$];
    rand bit [2:0] dxor[];
    rand bit [2:0] dprod[];
    rand bit [2:0] qand[$];
    rand bit [2:0] dor[];
    rand bit [2:0] x;
    rand int idx_sum;
    rand int both_sum;
    rand bit [3:0] amap[int];
    function new();
      amap[1] = 0;
      amap[5] = 0;
      amap[9] = 0;
    endfunction
    constraint c_n {n inside {[2 : 6]};}
    constraint c_sum_with {
      dsum.size() == n;
      dsum.sum() with (int'(item)) == 2 * n + 1;
    }
    constraint c_sum {
      qsum.size() == n + 1;
      qsum.sum() == 3'd5;
    }
    constraint c_prod_with {
      qprod.size() == n;
      qprod.product() with (int'(item) + 1) == 1 << n;
    }
    constraint c_and_with {
      dand.size() == n;
      dand.and() with (item[0]) == 1'b1;
    }
    constraint c_or {
      qor.size() == n - 1;
      qor.or() == 3'b110;
    }
    constraint c_xor_with {
      dxor.size() == n;
      dxor.xor() with (item ^ 3'(item.index)) == 3'd2;
    }
    constraint c_prod {
      dprod.size() == n;
      dprod.product() == 3'd1;
    }
    constraint c_and {
      qand.size() == n;
      qand.and() == 3'b101;
    }
    constraint c_or_with {
      dor.size() == n;
      dor.or() with (item & 3'b011) == 3'b010;
    }
    constraint c_index {idx_sum == dsum.sum() with (item.index);}
    constraint c_both {
      both_sum == dsum.sum() with (int'(item)) + qsum.sum() with (int'(item));
    }
    constraint c_inside {x inside {qor};}
    // Associative arrays are not resized, so their size takes no part
    constraint c_assoc {
      amap.size() == 3;
      amap.sum() with (int'(item)) == 20;
    }
  endclass

  // The only size-constrained array, and only its index is used
  class IndexTest;
    rand bit [2:0] d[];
    rand int idx_sum;
    constraint c {
      d.size() inside {[1 : 6]};
      idx_sum == d.sum() with (item.index);
    }
  endclass

  class CondTest;
    rand bit [2:0] d[];
    rand bit [2:0] q[$];
    rand bit mode;
    constraint c_cond {
      q.size() inside {[2 : 4]};
      if (mode) q.sum() with (int'(item)) == 9;
      else q.sum() with (int'(item)) == 2;
      foreach (q[i]) q[i] != 3'd5;
    }
  endclass

  initial begin
    static SizedTest t_sized = new();
    int randomize_result;
    repeat (20) begin
      int sum;
      int prod;
      int idxs;
      bit [2:0] qs;
      bit [2:0] ored;
      bit [2:0] xored;
      bit anded;
      bit found;
      randomize_result = t_sized.randomize();
      `checkd(randomize_result, 1);
      `checkd(t_sized.dsum.size(), t_sized.n);
      `checkd(t_sized.qsum.size(), t_sized.n + 1);
      `checkd(t_sized.qprod.size(), t_sized.n);
      `checkd(t_sized.dand.size(), t_sized.n);
      `checkd(t_sized.qor.size(), t_sized.n - 1);
      `checkd(t_sized.dxor.size(), t_sized.n);
      `checkd(t_sized.dprod.size(), t_sized.n);
      `checkd(t_sized.qand.size(), t_sized.n);
      `checkd(t_sized.dor.size(), t_sized.n);
      sum = 0;
      idxs = 0;
      foreach (t_sized.dsum[i]) begin
        sum += int'(t_sized.dsum[i]);
        idxs += i;
      end
      `checkd(sum, 2 * t_sized.n + 1);
      `checkd(t_sized.idx_sum, idxs);
      qs = 0;
      foreach (t_sized.qsum[i]) begin
        qs += t_sized.qsum[i];
        sum += int'(t_sized.qsum[i]);
      end
      `checkd(qs, 3'd5);
      `checkd(t_sized.both_sum, sum);
      prod = 1;
      foreach (t_sized.qprod[i]) prod *= int'(t_sized.qprod[i]) + 1;
      `checkd(prod, 1 << t_sized.n);
      anded = 1;
      foreach (t_sized.dand[i]) anded &= t_sized.dand[i][0];
      `checkd(anded, 1'b1);
      ored = 0;
      found = 0;
      foreach (t_sized.qor[i]) begin
        ored |= t_sized.qor[i];
        found |= t_sized.qor[i] == t_sized.x;
      end
      `checkd(ored, 3'b110);
      `checkd(found, 1'b1);
      xored = 0;
      foreach (t_sized.dxor[i]) xored ^= t_sized.dxor[i] ^ 3'(i);
      `checkd(xored, 3'd2);
      qs = 1;
      foreach (t_sized.dprod[i]) qs *= t_sized.dprod[i];
      `checkd(qs, 3'd1);
      qs = '1;
      foreach (t_sized.qand[i]) qs &= t_sized.qand[i];
      `checkd(qs, 3'b101);
      ored = 0;
      foreach (t_sized.dor[i]) ored |= t_sized.dor[i] & 3'b011;
      `checkd(ored, 3'b010);
      `checkd(t_sized.amap.size(), 3);
      sum = 0;
      foreach (t_sized.amap[k]) sum += int'(t_sized.amap[k]);
      `checkd(sum, 20);
    end
  end

  initial begin
    static IndexTest t_index = new();
    int randomize_result;
    repeat (20) begin
      int idxs;
      randomize_result = t_index.randomize();
      `checkd(randomize_result, 1);
      idxs = 0;
      foreach (t_index.d[i]) idxs += i;
      `checkd(t_index.idx_sum, idxs);
    end
  end

  initial begin
    static CondTest t_cond = new();
    int randomize_result;
    repeat (20) begin
      int n;
      int sum;
      n = 2 + $urandom_range(3);
      randomize_result = t_cond.randomize() with {
        d.size() == n;
        d.sum() with (int'(item)) == 2 * n;
      };
      `checkd(randomize_result, 1);
      `checkd(t_cond.d.size(), n);
      sum = 0;
      foreach (t_cond.d[i]) sum += int'(t_cond.d[i]);
      `checkd(sum, 2 * n);
      sum = 0;
      foreach (t_cond.q[i]) sum += int'(t_cond.q[i]);
      `checkd(sum, t_cond.mode ? 9 : 2);
    end
  end

  initial begin
    static XorTest t_xor = new();
    static SumTest t_sum = new();
    static AndTest t_and = new();
    static OrTest t_or = new();
    static ProductTest t_prod = new();
    int randomize_result;

    repeat (10) begin
      bit [7:0] exp;
      int i;

      // Test xor
      randomize_result = t_xor.randomize();
      `checkd(randomize_result, 1);
      exp = 0;
      foreach (t_xor.data[i]) exp ^= t_xor.data[i];
      `checkh(t_xor.result, exp)

      // Test sum
      randomize_result = t_sum.randomize();
      `checkd(randomize_result, 1);
      exp = 0;
      foreach (t_sum.data[i]) exp += t_sum.data[i];
      `checkh(t_sum.result, exp)

      // Test and
      randomize_result = t_and.randomize();
      `checkd(randomize_result, 1);
      exp = 8'hff;
      foreach (t_and.data[i]) exp &= t_and.data[i];
      `checkh(t_and.result, exp)

      // Test or
      randomize_result = t_or.randomize();
      `checkd(randomize_result, 1);
      exp = 0;
      foreach (t_or.data[i]) exp |= t_or.data[i];
      `checkh(t_or.result, exp)

      // Test product
      randomize_result = t_prod.randomize();
      `checkd(randomize_result, 1);
      exp = 8'd1;
      foreach (t_prod.data[i]) exp *= t_prod.data[i];
      `checkh(t_prod.result, exp)
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
