// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  initial begin
    // Decimal formatting of a wide value must scale well with the width
    bit [4094:0] pow;
    string zeros;
    string nines;
    pow = 1;
    for (int k = 0; k <= 1232; k++) begin
      if (k >= 1100) begin
        `checks($sformatf("%0d", pow), {"1", zeros});
        `checks($sformatf("%0d", pow - 1), nines);
        `checks($sformatf("%0d", -$signed(pow)), {"-1", zeros});
      end
      pow = pow * 10;
      zeros = {zeros, "0"};
      nines = {nines, "9"};
    end
    `checks($sformatf("%0d", 4095'd0), "0");
    `checks($sformatf("%0d", 65'h1_0000_0000_0000_0000), "18446744073709551616");
    `checks($sformatf("%0d", -65'sd1234567890123456789), "-1234567890123456789");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
