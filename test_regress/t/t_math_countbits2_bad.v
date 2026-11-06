// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  chandle my_vec[4];
  logic bool;
  int count;

  initial begin
    count = $countones(my_vec);  // Bad, must be bit-stream
    count = $countbits(my_vec, '0);  // Bad, must be bit-stream
    bool = $onehot(my_vec);  // Bad, must be bit-stream
    bool = $onehot0(my_vec);  // Bad, must be bit-stream
    $stop;
  end

endmodule
