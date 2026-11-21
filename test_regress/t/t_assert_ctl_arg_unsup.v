// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

module t;
  let OFF = 4;
  let FAILOFF = 9;
  let UNIQUE = 32;
  let PRIORITY = 128;
  logic directive_type = 1'b1;
  int control_type = 4;

  initial begin
    $assertcontrol(FAILOFF, UNIQUE);
    $assertcontrol(control_type, PRIORITY);
    $assertcontrol(OFF, 1, directive_type);
  end
endmodule
