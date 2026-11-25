// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Formats a time in a 1 s time unit
module seconds_unit;
  timeunit 1s; timeprecision 1fs;
  function automatic string fmt(realtime r);
    return $sformatf("%t", r);
  endfunction
endmodule

module t;

  timeunit 1ns; timeprecision 1ps;

  // Number of characters of s from index start on that are not '0'
  function automatic int nonzeros(string s, int start);
    nonzeros = 0;
    for (int k = start; k < s.len(); ++k) if (s[k] != "0") ++nonzeros;
  endfunction

  seconds_unit su ();

  initial begin
    time t;
    realtime r;
    int units_number;
    int precision_number;
    int i;
    string s;
    t = 12345ns;
    r = 1.5ns;

    // Precision beyond 18 digits prints the requested number of digits
    units_number = -9;
    precision_number = 999;
    $timeformat(units_number, precision_number, "", 0);
    s = $sformatf("%t", t);
    `checkd(s.len(), 6 + 999);
    `checks(s.substr(0, 5), "12345.");
    `checkd(nonzeros(s, 6), 0);
    s = $sformatf("%t", r);
    `checkd(s.len(), 2 + 999);
    `checks(s.substr(0, 2), "1.5");
    `checkd(nonzeros(s, 3), 0);
    // Precision above the 1048576 maximum prints 1048576 digits
    precision_number = 1048577;
    $timeformat(units_number, precision_number, "", 0);
    s = $sformatf("%t", t);
    `checkd(s.len(), 6 + 1048576);
    `checkd(nonzeros(s, 6), 0);
    precision_number = 2147483647;
    $timeformat(units_number, precision_number, "", 0);
    s = $sformatf("%t", t);
    `checkd(s.len(), 6 + 1048576);
    // Negative precision prints no fraction
    precision_number = -5;
    $timeformat(units_number, precision_number, "", 0);
    `checks($sformatf("%t", t), "12345");
    // Units above 2 saturate to 100 s
    units_number = 1000;
    precision_number = 12;
    $timeformat(units_number, precision_number, "", 0);
    `checks($sformatf("%t", t), "0.000000123450");
    i = $sscanf("3", "%t", t);
    `checkd(i, 1);
    `checkd(t, 64'd300000000000);
    t = 12345ns;
    // Units below -15 saturate to 1 fs
    units_number = -1000;
    precision_number = 0;
    $timeformat(units_number, precision_number, "", 0);
    `checks($sformatf("%t", t), "12345000000");
    // Digits finer than the time unit print as zeros
    units_number = -15;
    precision_number = 18;
    $timeformat(units_number, precision_number, "", 0);
    `checks($sformatf("%t", t), "12345000000.000000000000000000");

    // Real times print every requested digit, also far below the time unit
    $timeformat(-15, 6, " fs", 0);
    `checks(su.fmt(1.23456e-16), "0.123456 fs");
    `checks(su.fmt(9.87654321e-14), "98.765432 fs");
    $timeformat(-12, 9, " ps", 0);
    `checks(su.fmt(9.87654321e-14), "0.098765432 ps");
    $timeformat(-9, 12, " ns", 0);
    `checks(su.fmt(1.23456e-16), "0.000000123456 ns");

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
