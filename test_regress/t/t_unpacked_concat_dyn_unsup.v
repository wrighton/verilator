// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A queue or dynamic array item in an unpacked array concatenation to a fixed-size array
module t;
  typedef int int_q_t[$];
  int i2[2];
  int i3[3];
  string s3[3];
  int_q_t qa[2];
  int q[$];
  int d[];
  string sq[$];
  int_q_t qq[$];
  int_q_t tq;

  initial begin
    i2 = {q};
    i3 = {q, 3};
    i2 = {d};
    s3 = {sq, "x"};
    qa = {qq};
    qa = {q, q};  // Elements, supported
    i2 = {tq};
  end
endmodule
