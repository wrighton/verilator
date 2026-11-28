// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// %p of a type nesting descending fixed-size arrays and queues many levels deep

module t;
  typedef int d0_t[3:2];
  typedef d0_t q1_t[$];
  typedef q1_t d1_t[3:2];
  typedef d1_t q2_t[$];
  typedef q2_t d2_t[3:2];
  typedef d2_t q3_t[$];
  typedef q3_t d3_t[3:2];
  typedef d3_t q4_t[$];
  typedef q4_t d4_t[3:2];
  typedef d4_t q5_t[$];
  typedef q5_t d5_t[3:2];
  typedef d5_t q6_t[$];
  typedef q6_t d6_t[3:2];
  typedef d6_t q7_t[$];
  typedef q7_t d7_t[3:2];
  typedef d7_t q8_t[$];
  typedef q8_t d8_t[3:2];
  typedef d8_t q9_t[$];
  typedef q9_t d9_t[3:2];
  typedef d9_t q10_t[$];
  typedef q10_t d10_t[3:2];
  typedef d10_t q11_t[$];
  typedef q11_t d11_t[3:2];
  typedef d11_t q12_t[$];
  typedef q12_t d12_t[3:2];
  typedef d12_t q13_t[$];
  typedef q13_t d13_t[3:2];
  typedef d13_t q14_t[$];
  typedef q14_t d14_t[3:2];
  typedef d14_t q15_t[$];
  typedef q15_t d15_t[3:2];
  typedef d15_t q16_t[$];
  typedef q16_t d16_t[3:2];
  typedef d16_t q17_t[$];
  typedef q17_t d17_t[3:2];
  typedef d17_t q18_t[$];
  typedef q18_t d18_t[3:2];
  typedef d18_t q19_t[$];
  typedef q19_t d19_t[3:2];
  typedef d19_t q20_t[$];
  typedef q20_t d20_t[3:2];
  typedef d20_t q21_t[$];
  typedef q21_t d21_t[3:2];
  typedef d21_t q22_t[$];
  typedef q22_t d22_t[3:2];
  typedef d22_t q23_t[$];
  typedef q23_t d23_t[3:2];
  typedef d23_t q24_t[$];
  typedef q24_t d24_t[3:2];
  typedef d24_t q25_t[$];
  typedef q25_t d25_t[3:2];
  typedef d25_t q26_t[$];
  typedef q26_t d26_t[3:2];
  typedef d26_t q27_t[$];
  typedef q27_t d27_t[3:2];
  typedef d27_t q28_t[$];
  typedef q28_t d28_t[3:2];
  d28_t a;

  initial $display("%p", a);
endmodule
