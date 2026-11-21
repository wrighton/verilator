// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2009 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package testpackage;
  localparam PARAM = 1024 >> 3;
endpackage
import testpackage::*;

module t;

  localparam P3 = 3;
  localparam P4 = f_add(P3, 1);
  localparam P8 = f_add2(P3, P3, f_add(1, 1));
  localparam P5 = f_while(7);
  localparam P16 = f_for(P4);
  localparam P18 = f_case(P4);
  localparam P6 = f_return(P4);
  localparam P128 = f_package();
  localparam [15:0] PSEL = f_concat_sel(16'h4321);
  localparam P0 = f_out_of_bounds(3);
  localparam P1 = f_desc_out_of_bounds(5);
  localparam P0_ABOVE = f_desc_out_of_bounds(6);
  localparam P0_BELOW = f_desc_out_of_bounds(2);
  localparam P_LOOP = f_out_of_bounds_loop();
  localparam P_REENTER = f_reenter(2);
  localparam P_PAST_END = f_past_end();
  typedef int five_t[5];
  localparam five_t FIVE = '{1, 2, 3, 4, 5};
  localparam P_PAST_END_PARAM = f_get5(FIVE, 3) * 100 + f_get5(FIVE, 6) * 10 + f_get5(FIVE, 3);
  localparam P_RECURSE = f_recurse();
  localparam P_MUTUAL = f_mutual_f(1);

  typedef struct packed {logic [7:0] data;} type_t;
  typedef type_t [1:0] flist;
  localparam flist PLIST = {8'd4, 8'd8};
  localparam flist PARR = f_list_swap_2(PLIST);
  typedef struct packed {
    logic first;
    logic second;
    logic [31:0] data;
  } bigstruct_t;
  localparam bigstruct_t bigparam = f_return_struct(1'b1, 1'b0, 32'hfff12fff);

  initial begin
`ifdef TEST_VERBOSE
    $display("P5=%0d P8=%0d P16=%0d P18=%0d", P5, P8, P16, P18);
`endif
    if (P3 !== 3) $stop;
    if (P4 !== 4) $stop;
    if (P5 !== 5) $stop;
    if (P6 !== 6) $stop;
    if (P8 !== 8) $stop;
    if (P16 !== 16) $stop;
    if (P18 !== 18) $stop;
    if (PARR[0] != PLIST[1]) $stop;
    if (PARR[1] != PLIST[0]) $stop;
    if (bigparam.first != 1'b1) $stop;
    if (bigparam.second != 1'b0) $stop;
    if (bigparam.data != 32'hfff12fff) $stop;
    if (P128 != 128) $stop;
    if (PSEL != 16'h1234) $stop;
    if (P0 !== 0) $stop;
    if (P1 !== 1) $stop;
    if (P0_ABOVE !== 0) $stop;
    if (P0_BELOW !== 0) $stop;
    if (P_LOOP !== 140) $stop;
    if (P_REENTER !== 2000) $stop;
    if (P_PAST_END !== 404) $stop;
    if (P_PAST_END_PARAM !== 404) $stop;
    if (P_RECURSE !== 150150) $stop;
    if (P_MUTUAL !== 1000) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end

  function integer f_package();
    return PARAM;
  endfunction

  // Array read out of bounds gives the default value of the element type
  function automatic integer f_out_of_bounds(input [31:0] i);
    int a[3] = '{default: 7};
    return a[i];
  endfunction

  // Likewise of a typedef'd array, indexed from 5 down to 3
  typedef int desc_t[5:3];
  function automatic integer f_desc_out_of_bounds(input integer i);
    desc_t a;
    a[5] = 1;
    return a[i];
  endfunction

  // Reads past the end through the same select leave the elements unchanged
  function automatic integer f_out_of_bounds_loop();
    int a[5] = '{10, 20, 30, 40, 50};
    integer s = 0;
    for (int i = 3; i < 7; i++) s += a[i];
    return s + a[4];
  endfunction

  // A static variable passed by value, then changed by re-entering its function
  typedef int four_t[4];
  function automatic integer f_reenter(int n);
    static four_t s;
    integer r;
    s[0] = n;
    r = (n == 2) ? f_reentered(s) : 0;
    return r;
  endfunction
  function automatic integer f_reentered(four_t p);
    integer b;
    b = f_reenter(1);
    return p[0] * 1000 + b;
  endfunction

  // Reads past the end of a passed array leave the caller's array unchanged
  function automatic integer f_get5(five_t tbl, int i);
    return tbl[i];
  endfunction
  function automatic integer f_past_end();
    five_t t;
    foreach (t[i]) t[i] = i + 1;
    return f_get5(t, 3) * 100 + f_get5(t, 6) * 10 + f_get5(t, 3);
  endfunction

  // A recursive function passing its array argument down
  function automatic integer f_down(int n, five_t p);
    if (n == 0) return p[0];
    return p[n] + f_down(n - 1, p);
  endfunction
  function automatic integer f_recurse();
    five_t a;
    integer x;
    foreach (a[i]) a[i] = (i + 1) * 10;
    x = f_down(4, a);
    return x * 1000 + a[0] + a[1] + a[2] + a[3] + a[4];
  endfunction

  // Mutually recursive functions, the caller changing its passed array after the call
  function automatic integer f_mutual_g(int n, five_t p);
    integer r;
    r = 0;
    if (n > 0) r = f_mutual_f(n - 1);
    return p[0] * 100 + r;
  endfunction
  function automatic integer f_mutual_f(int n);
    five_t b;
    integer x;
    b[0] = 5;
    x = f_mutual_g(n, b);
    b[0] = 9;
    return x;
  endfunction

  // An out-of-bounds index wider than 32 bits, read and written; in a generate condition, where
  // the index keeps its full width
  if (f_wide_out_of_bounds(64'h1_0000_0000) != 21) $error;
  // verilator lint_off WIDTHTRUNC
  function automatic integer f_wide_out_of_bounds(input [63:0] i);
    int a[3] = '{default: 7};
    a[i] = 5;
    return a[i] + a[0] + a[1] + a[2];
  endfunction
  // verilator lint_on WIDTHTRUNC

  function integer f_add(input [31:0] a, input [31:0] b);
    f_add = a + b;
  endfunction

  // Speced ok: function called from function
  function integer f_add2(input [31:0] a, input [31:0] b, input [31:0] c);
    f_add2 = f_add(a, b) + c;
  endfunction

  // Speced ok: local variables
  function integer f_for(input [31:0] a);
    integer i;
    integer times;
    begin
      times = 1;
      for (i = 0; i < a; i = i + 1) times = times * 2;
      f_for = times;
    end
  endfunction

  function integer f_while(input [31:0] a);
    integer i;
    begin
      i = 0;
      begin : named
        f_while = 1;
      end : named
      while (i <= a) begin
        if (i[0]) f_while = f_while + 1;
        i = i + 1;
      end
    end
  endfunction

  // Speced ok: local variables
  function integer f_case(input [31:0] a);
    case (a)
      32'd1: f_case = 1;
      32'd0, 32'd4: f_case = 18;
      32'd1234: begin
        $display("never get here");
        $stop;
      end
      default: f_case = 99;
    endcase
  endfunction

  function automatic integer f_return(input [31:0] a);
    integer out = 2;
    while (1) begin
      out = out + 1;
      if (a > 1) break;
    end
    while (1) begin
      out = out + 1;
      if (a > 1) return 2 + out;
    end
    f_return = 0;
  endfunction

  function flist f_list_swap_2(input flist in_list);
    f_list_swap_2[0].data = in_list[1].data;
    f_list_swap_2[1].data = in_list[0].data;
  endfunction

  function bigstruct_t f_return_struct(input first, input second, input [31:0] data);
    bigstruct_t result;
    result.data = data;
    result.first = first;
    result.second = second;
    return result;
  endfunction

  function [15:0] f_concat_sel(input [15:0] in);
    reg [3:0] tmp1, tmp2, tmp3, tmp4;
    {tmp4, tmp3, tmp2, tmp1} = in;
    f_concat_sel = {tmp1, tmp2, tmp3, tmp4};
  endfunction

endmodule
