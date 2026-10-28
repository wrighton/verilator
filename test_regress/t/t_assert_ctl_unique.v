// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// $assertcontrol of unique/unique0/priority violation checks (IEEE 1800-2023 Table 20-6)

module t;
  let ON = 3;
  let OFF = 4;
  let CONCURRENT = 1;
  let UNIQUE = 32;
  let UNIQUE0 = 64;
  let PRIORITY = 128;

  int y;

  // v == 0 violates unique, priority and unique if (none matched);
  // v == 3 violates unique, unique0 and unique if (multiple matched)
  task automatic check(input logic [1:0] v);
    $display("check v=%0d", v);
    unique case (1'b1)
      v[0]: y = 0;
      v[1]: y = 1;
    endcase
    unique0 case (1'b1)
      v[0]: y = 2;
      v[1]: y = 3;
    endcase
    priority case (1'b1)
      v[0]: y = 4;
      v[1]: y = 5;
    endcase
    unique if (v[0]) y = 6;
    else if (v[1]) y = 7;
  endtask

  initial begin
    check(0);
    check(3);
    $assertcontrol(OFF, CONCURRENT);
    check(0);
    $assertcontrol(OFF, UNIQUE);
    check(0);
    check(3);
    $assertcontrol(OFF, UNIQUE0 | PRIORITY);
    check(0);
    check(3);
    $assertcontrol(ON, UNIQUE0);
    check(0);
    check(3);
    $assertcontrol(ON, UNIQUE | UNIQUE0 | PRIORITY);
    check(0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
