// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
endclass

module t;
  typedef string string_q_t[$];
  typedef Cls cls_q_t[$];
  typedef struct {byte a;} s_t;
  typedef s_t s_q_t[$];

  logic [39:0] w;
  string_q_t sq;
  cls_q_t cq;
  s_q_t stq;

  initial begin
    sq = string_q_t'(w);
    sq = string_q_t'({>>{w}});
    cq = cls_q_t'(w);
    stq = s_q_t'(w);
  end
endmodule
