// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  typedef integer dyn_t[];
  typedef integer queue_t[$];
  integer a[];
  dyn_t b;
  queue_t q;

  initial begin
    if ($bits(a) != 0) $stop;
    a = new[10];
    if ($bits(a) != 10 * 32) $stop;
    if ($bits(b) != 0) $stop;
    if ($bits(q) != 0) $stop;
  end

endmodule
