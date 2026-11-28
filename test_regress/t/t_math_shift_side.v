// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Cls;
  int m_n_bits;

  function int get_n_bytes;
    return ((m_n_bits - 1) / 8) + 1;
  endfunction

endclass

module t;

  int i;
  longint q;
  int iq[$];
  longint qq[$];

  initial begin
    Cls c;
    c = new;

    c.m_n_bits = 23;
    if (c.get_n_bytes() != 3) $stop;

    i = 1 << c.get_n_bytes();
    if (i != 8) $stop;

    i = 32'h1234 >> c.get_n_bytes();
    if (i != 32'h246) $stop;

    i = 32'shffffffff >>> c.get_n_bytes();
    if (i != 32'hffffffff) $stop;

    // Oversized constant shift must still evaluate the shifted operand
    iq = '{1, 2, 3};
    i = iq.pop_front() << 8'd40;
    if (i != 0) $stop;
    if (iq.size() != 2) $stop;
    i = iq.pop_front() >> 8'd40;
    if (i != 0) $stop;
    if (iq.size() != 1) $stop;
    qq = '{1, 2};
    q = qq.pop_front() << 8'd70;
    if (q != 0) $stop;
    if (qq.size() != 1) $stop;

    // Also when shifted again by a constant, the first amount being too wide for an integer
    // or not, or in range
    // verilator lint_off WIDTH
    iq = '{5, 6, 7, 8, 9, 10};
    i = (iq.pop_front() >> 40'h1_0000_0000) >> 3;
    `checkd(i, 0);
    i = (iq.pop_front() << 40'h1_0000_0000) << 3;
    `checkd(i, 0);
    i = (iq.pop_front() >> 40'h1_0000_0000) << 3;
    `checkd(i, 0);
    i = (iq.pop_front() << 32'h8000_0000) >> 3;
    `checkd(i, 0);
    i = (iq.pop_front() >> 3) >> 40'h1_0000_0000;
    `checkd(i, 0);
    // verilator lint_on WIDTH
    i = (iq.pop_front() << 4) >> 2;
    `checkd(i, 40);
    `checkd(iq.size(), 0);

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
