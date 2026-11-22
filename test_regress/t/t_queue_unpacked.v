// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  typedef string sarray_t[2];
  typedef sarray_t q_sarray_t[$];

  typedef bit [95:0] wide_t;
  typedef wide_t warray_t[2];
  typedef warray_t q_warray_t[$];

  initial begin
    begin
      q_sarray_t iq;
      sarray_t a;
      sarray_t b0;
      sarray_t b1;

      a[0] = "hello";
      a[1] = "world";
      iq.push_back(a);
      a[0] = "bye";
      a[1] = "world";
      iq.push_back(a);

      b0 = iq[0];
      b1 = iq[1];
      `checks(b0[0], "hello");
      `checks(b0[1], "world");
      `checks(b1[0], "bye");
      `checks(b1[1], "world");

      iq[2][0] = "goodbye";
      iq[2][1] = "world";
      `checks(iq[2][0], "goodbye");
      `checks(iq[2][1], "world");
    end

    begin
      q_warray_t iq;
      warray_t a;
      warray_t b0;

      a[0] = "abcdefg_ijkl";
      a[1] = "012123123128";
      iq.push_back(a);

      b0 = iq[0];
      `checks(b0[0], "abcdefg_ijkl");
      `checks(b0[1], "012123123128");

      // Test: selects of a wide element of a queued array
      `checkh(iq[0][0][7:0], 8'h6c);
      `checkh(iq[0][1][3], 1'b1);
    end

    begin
      // Test: selects of a wide element of a queued array at runtime indices, popped once
      typedef bit [94:0] w95_t;
      typedef w95_t w95_array_t[3:1];
      w95_array_t q[$];
      w95_array_t row;
      int j;
      int b;
      bit got;
      bit [6:0] got7;
      row = '{95'h1, 95'h4000_0000_0000_0000_0000_0002, 95'h4};
      q.push_back(row);
      row = '{95'h0, 95'h0, 95'h0};
      q.push_back(row);
      j = $urandom_range(2, 2);
      b = $urandom_range(94, 94);
      `checkh(q[0][j][b], 1'b1);
      `checkh(q[0][j][b-:7], 7'h40);
      got = q.pop_front()[j][1];
      `checkh(got, 1'b1);
      `checkh(q.size(), 1);
      got7 = q.pop_front()[j][b-:7];
      `checkh(got7, 7'h0);
      `checkh(q.size(), 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
