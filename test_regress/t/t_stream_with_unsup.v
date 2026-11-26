// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  byte unsigned data[];
  byte unsigned q[$];
  byte unsigned q2[$];
  byte unsigned r[$];
  byte unsigned f[2:5];
  int n;
  initial begin
    n = 2;
    {>>{data with [0:n-1]}} = 16'h1234;
    {>>{f with [n+:2]}} = 16'h1234;
    r = {>>{q with [0:n-1], q2 with [1:2]}};
  end
endmodule
