// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A kill of the unique, unique0 or priority checks removes their pending violation reports, also
// when they are turned on again in the same time step, unlike a kill of other assertion types
// (IEEE 1800-2023 20.11, Table 20-6)
module t;
  let KILL = 5;
  let ON = 3;
  let CONCURRENT = 1;
  let PRIORITY = 128;

  // $assertkill is $assertcontrol(5, 15, 7), not of violation checks
  initial begin : not_killed_assertkill
    logic [1:0] v;
    #1;
    v = 2'b11;
    unique case (1'b1)
      v[0]: ;
      v[1]: ;
    endcase
    $assertkill;
    $asserton;
  end

  initial begin : not_killed_other_type
    logic [1:0] v;
    #2;
    v = 2'b11;
    unique case (1'b1)
      v[0]: ;
      v[1]: ;
    endcase
    $assertcontrol(KILL, CONCURRENT | PRIORITY);
    $assertcontrol(ON, CONCURRENT | PRIORITY);
  end

  initial begin : killed_type
    logic [1:0] v;
    #3;
    v = 2'b00;
    priority case (1'b1)
      v[0]: ;
      v[1]: ;
    endcase
    $assertcontrol(KILL, PRIORITY);
    $assertcontrol(ON, PRIORITY);
  end

  initial begin
    #5;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
