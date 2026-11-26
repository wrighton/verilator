// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Hierarchical references to automatic variables from outside their scope
// (IEEE 1800-2023 6.21) in fork branches, moved into tasks: into another
// instance of the same module

module leaf (
    input int seed,
    output int result
);
  initial begin
    fork
      begin : worker
        begin : frame
          automatic int payload;
          payload = seed;
          for (int i = 0; i < 2; ++i) begin : inner
            #1;
            result = $root.t.v.worker.frame.payload;
          end
        end
      end
    join_none
  end
endmodule

module t;
  int a, b;
  leaf u (
      29,
      a
  );
  leaf v (
      73,
      b
  );
  initial begin
    #10;
    $finish;
  end
endmodule
