// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The conditions of a unique, unique0 or priority if, and the items of a unique, unique0 or
// priority case, are evaluated once by the statement and its violation check (IEEE 1800-2023
// 12.4.2, 12.5.3)
module t;
  int n[19];
  function automatic bit f(int i, bit v);
    ++n[i];
    return v;
  endfunction
  function automatic int g(int i, int v);
    ++n[i];
    return v;
  endfunction
  // Alternately true and false, so a condition evaluated twice takes another branch
  bit tog = 1'b0;
  function automatic bit flip();
    tog = !tog;
    return tog;
  endfunction

  // Changes the case expression
  int sel;
  function automatic int mutate(int i, int v);
    ++n[i];
    sel = v;
    return 3;
  endfunction

  function automatic int in_function();
    unique if (f(12, 1'b0)) return 1;
    else if (f(13, 1'b1)) return 2;
    return 0;
  endfunction

  int y;
  initial begin
    // All conditions of a unique or unique0 if, each once
    unique if (f(0, 1'b1)) y = 1;
    else if (f(1, 1'b0)) y = 2;
    `checkd(y, 1);
    unique0 if (f(2, 1'b0)) y = 1;
    else if (f(3, 1'b0)) y = 2;
    `checkd(y, 1);
    // A priority if, up to its first true condition
    priority if (f(4, 1'b1)) y = 3;
    else if (f(5, 1'b1)) y = 4;
    `checkd(y, 3);
    // Each item of a unique or unique0 case once
    unique case (1'b1)
      f(6, 1'b0): y = 5;
      f(7, 1'b1): y = 6;
    endcase
    `checkd(y, 6);
    unique0 case (g(8, 3))
      g(9, 1): y = 7;
      g(10, 3): y = 8;
    endcase
    `checkd(y, 8);
    // Range bounds
    unique case (5) inside
      [g(11, 0) : g(11, 9)]: y = 9;
    endcase
    `checkd(y, 9);
    y = in_function();
    `checkd(y, 2);
    // A priority case, up to its first matching item
    priority case (1'b1)
      f(14, 1'b1): y = 10;
      f(15, 1'b1): y = 11;
    endcase
    `checkd(y, 10);
    `checkd(n[0], 1);
    `checkd(n[1], 1);
    `checkd(n[2], 1);
    `checkd(n[3], 1);
    `checkd(n[4], 1);
    `checkd(n[5], 0);
    `checkd(n[6], 1);
    `checkd(n[7], 1);
    `checkd(n[8], 1);
    `checkd(n[9], 1);
    `checkd(n[10], 1);
    `checkd(n[11], 2);
    `checkd(n[12], 1);
    `checkd(n[13], 1);
    `checkd(n[14], 1);
    `checkd(n[15], 0);

    // The case expression is evaluated before the item expressions, which do not change the
    // value it is compared as
    sel = 3;
    unique case (sel)
      mutate(16, 8): y = 14;
      8: y = 15;
      default: y = 16;
    endcase
    `checkd(sel, 8);
    `checkd(y, 14);
    `checkd(n[16], 1);
    sel = 3;
    unique0 case (sel)
      mutate(17, 8): y = 17;
      8: y = 18;
    endcase
    `checkd(y, 17);
    `checkd(n[17], 1);
    sel = 3;
    unique case (sel) inside
      [mutate(18, 8) : 5]: y = 19;
      [8 : 9]: y = 20;
    endcase
    `checkd(y, 19);
    `checkd(n[18], 1);

    // Pure conditions are not lifted
    y = 10;
    unique if (y == 10) y = 12;
    else if (y == 11) y = 13;
    `checkd(y, 12);

    // The branch of the value the condition had in the check
    tog = 1'b0;
    unique if (flip()) y = 1;
    else if (1'b0) y = 2;
    `checkd(y, 1);
    tog = 1'b0;
    unique0 if (flip()) y = 3;
    else if (1'b0) y = 4;
    `checkd(y, 3);
    tog = 1'b0;
    priority if (flip()) y = 5;
    else if (1'b1) y = 6;
    `checkd(y, 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
