// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef byte bq_t[$];
  // A cast to a queue is not a constant
  localparam bq_t QP = bq_t'(16'h4142);
  // Nor is a stream into a queue
  localparam bit [15:0] P = 16'h4142;
  localparam bq_t SP = {>>{P}};
  initial $display("%p %p", QP, SP);
endmodule
