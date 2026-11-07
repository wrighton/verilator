// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Kristof Marien
// SPDX-License-Identifier: CC0-1.0

// randc cycles (IEEE 1800-2023 18.4.2) of a randomize() that first solves the size of
// an array, then the elements

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class RandcSized;
  randc bit [1:0] x;
  rand bit [7:0] d[];
  constraint c {
    x != 0;
    d.size() == 2;
    foreach (d[i]) d[i] < 8'd10;
  }
endclass

// The size depends on the randc variable
class RandcSize;
  randc bit [1:0] n;
  rand bit [7:0] q[];
  constraint c {
    n != 0;
    q.size() == 32'(n);
    foreach (q[i]) q[i] == 8'(i);
  }
endclass

// The size, from the randc variable, and element constraints are inline
class RandcInlineSize;
  randc bit [1:0] n;
  rand bit [7:0] q[];
  constraint c {n != 0;}
endclass

// The size and element constraints are inline; randomize() with also solves the sizes first
class RandcInline;
  randc bit [1:0] x;
  rand bit [7:0] d[];
  constraint c {x != 0;}
endclass

module t;
  initial begin
    automatic RandcSized sized[3];
    automatic RandcSize size = new;
    automatic RandcInline inl = new;
    automatic RandcInlineSize inl_size = new;
    automatic int randomize_result;
    foreach (sized[o]) sized[o] = new;
    for (int trial = 0; trial < 4; ++trial) begin
      // Values seen in this cycle
      automatic bit [3:0] sized_seen[3] = '{0, 0, 0};
      automatic bit [3:0] size_seen = 0;
      automatic bit [3:0] inl_seen = 0;
      automatic bit [3:0] inl_size_seen = 0;
      for (int i = 0; i < 3; ++i) begin
        foreach (sized[o]) begin
          randomize_result = sized[o].randomize();
          `checkd(randomize_result, 1);
          `checkd(sized[o].x == 0, 0);
          `checkd(sized[o].d.size(), 2);
          foreach (sized[o].d[k]) `checkd(sized[o].d[k] < 8'd10, 1);
          `checkd(sized_seen[o][sized[o].x], 0);
          sized_seen[o][sized[o].x] = 1;
        end

        randomize_result = size.randomize();
        `checkd(randomize_result, 1);
        `checkd(size.n == 0, 0);
        `checkd(size.q.size(), 32'(size.n));
        foreach (size.q[k]) `checkd(size.q[k], 8'(k));
        `checkd(size_seen[size.n], 0);
        size_seen[size.n] = 1;

        randomize_result = inl.randomize() with {
          d.size() == 2;
          foreach (d[k]) d[k] < 8'd10;
        };
        `checkd(randomize_result, 1);
        `checkd(inl.x == 0, 0);
        `checkd(inl.d.size(), 2);
        foreach (inl.d[k]) `checkd(inl.d[k] < 8'd10, 1);
        `checkd(inl_seen[inl.x], 0);
        inl_seen[inl.x] = 1;

        randomize_result = inl_size.randomize() with {
          q.size() == 32'(n);
          foreach (q[k]) q[k] == 8'(k);
        };
        `checkd(randomize_result, 1);
        `checkd(inl_size.n == 0, 0);
        `checkd(inl_size.q.size(), 32'(inl_size.n));
        foreach (inl_size.q[k]) `checkd(inl_size.q[k], 8'(k));
        `checkd(inl_size_seen[inl_size.n], 0);
        inl_size_seen[inl_size.n] = 1;
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
