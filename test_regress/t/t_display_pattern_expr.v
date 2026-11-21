// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef struct {
  bit [6:0] value;
  struct {bit [6:0] value;} nested;
} state_t;

typedef bit [6:0] values_t[2];

class C;
  state_t state[2];
  values_t values;
endclass

class ArrayFormatter;
  typedef bit [6:0] row_t[7];
  row_t values[2][2][2];
  bit [6:0] descending[1:0][3:4][5:4][2:8];
  string messages[2];
  bit [6:0] minimums[$];
  bit [6:0] lowest[1];
  int rows_checked;

  function void check_rows(int count, bit [6:0] cycle);
    // A runtime loop bound keeps the subarray index variable during slicing.
    for (int row = 0; row < count; ++row) begin
      string expected;
      expected = $sformatf("'{'h%0h, 'h%0h, 'h%0h, 'h%0h, 'h%0h, 'h%0h, 'h%0h}",
                           cycle + 7'(row * 7), cycle + 7'(row * 7 + 1),
                           cycle + 7'(row * 7 + 2), cycle + 7'(row * 7 + 3),
                           cycle + 7'(row * 7 + 4), cycle + 7'(row * 7 + 5),
                           cycle + 7'(row * 7 + 6));
      messages[row] = $sformatf("%p", values[0][0][row]);
      `checks(messages[row], expected);
      expected = $sformatf("'{'h%0h, 'h%0h, 'h%0h, 'h%0h, 'h%0h, 'h%0h, 'h%0h}",
                           cycle + 7'(row * 7 + 21), cycle + 7'(row * 7 + 22),
                           cycle + 7'(row * 7 + 23), cycle + 7'(row * 7 + 24),
                           cycle + 7'(row * 7 + 25), cycle + 7'(row * 7 + 26),
                           cycle + 7'(row * 7 + 27));
      messages[row] = $sformatf("%p", descending[1][3][5 - row]);
      `checks(messages[row], expected);
      // An array method also consumes the bounds-checked subarray whole.
      minimums = values[0][0][row].min();
      `checkd(minimums.size(), 1);
      `checkd(minimums[0], cycle + 7'(row * 7));
      // Also when the method result is converted to a fixed-size array
      lowest = descending[1][3][5 - row].min();
      `checkd(lowest[0], cycle + 7'(row * 7 + 21));
      ++rows_checked;
    end
    // The bounds-check fallback remains a whole default-valued subarray.
    `checks($sformatf("%p", values[0][0][count + 2]), "'{'h0, 'h0, 'h0, 'h0, 'h0, 'h0, 'h0}");
    minimums = values[0][0][count + 2].min();
    `checkd(minimums.size(), 1);
    `checkd(minimums[0], 0);
    lowest = '{7'h7f};
    lowest = values[0][0][count + 2].min();
    `checkd(lowest[0], 0);
  endfunction

  function void check_unrolled_defaults();
    // Unrolling folds each out-of-range bounds check to the default subarray itself.
    for (int row = 2; row < 4; ++row) begin
      messages[row - 2] = $sformatf("%p", values[1][1][row]);
      `checks(messages[row - 2], "'{'h0, 'h0, 'h0, 'h0, 'h0, 'h0, 'h0}");
      minimums = '{7'h7f, 7'h7f};
      minimums = values[1][1][row].min();
      `checkd(minimums.size(), 1);
      `checkd(minimums[0], 0);
      lowest = '{7'h7f};
      lowest = values[1][1][row].min();
      `checkd(lowest[0], 0);
      ++rows_checked;
    end
  endfunction
endclass

module t (
    input clk
);
  C c;
  ArrayFormatter formatter;
  bit [6:0] cyc = 0;

  initial begin
    c = new;
    formatter = new;
  end

  always @(posedge clk) begin
    string expected0;
    string expected1;
    cyc++;
    c.state[0].value = cyc;
    c.state[0].nested.value = cyc + 7'd1;
    c.state[1].value = cyc + 7'd2;
    c.state[1].nested.value = cyc + 7'd3;
    expected0 = $sformatf("'{value:'h%0h, nested:'{value:'h%0h}}", cyc, cyc + 7'd1);
    expected1 = $sformatf("'{value:'h%0h, nested:'{value:'h%0h}}", cyc + 7'd2, cyc + 7'd3);
    `checks($sformatf("%p", c.state), {"'{", expected0, ", ", expected1, "}"});
    `checks($sformatf("%p", c.state[0]), expected0);
    c.values = '{cyc + 7'd4, cyc + 7'd5};
    `checks($sformatf("%p", c.values), $sformatf("'{'h%0h, 'h%0h}", cyc + 7'd4, cyc + 7'd5));
    for (int row = 0; row < 2; ++row) begin
      for (int item = 0; item < 7; ++item) begin
        formatter.values[0][0][row][item] = cyc + 7'(row * 7 + item);
        formatter.values[1][1][row][item] = cyc + 7'(row * 7 + item + 42);
        formatter.descending[1][3][5 - row][2 + item] = cyc + 7'(row * 7 + item + 21);
      end
    end
    formatter.check_rows(cyc == 1 ? 1 : 2, cyc);
    formatter.check_unrolled_defaults();
    if (cyc == 3) begin
      `checkd(formatter.rows_checked, 11);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
