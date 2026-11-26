// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

module t;
  // An unpacked array assigned whole, with an intra-assignment timing control, is assigned
  // once, after a single wait, with the value it had when the assignment started
  int r2[3][4];
  int row[4];
  int row_dly[4];
  int row_nba[4];
  logic clk = 1'b0;
  int j;
  bit joined = 1'b0;

  initial begin
    foreach (r2[x, y]) r2[x][y] = 10 * x + y + 1;
    j = $urandom_range(1, 1);
    row = '{7, 7, 7, 7};
    row_dly = '{7, 7, 7, 7};
    row_nba = '{7, 7, 7, 7};
    fork
      row = @(posedge clk) r2[j];
      row_dly = #3 r2[1];
      row_nba <= @(posedge clk) r2[j+1];
      begin
        #1 r2[1] = '{0, 0, 0, 0};  // After the values were taken
        r2[2] = '{0, 0, 0, 0};
        #1;
        `checkp(row, "'{'h7, 'h7, 'h7, 'h7}");
        `checkp(row_nba, "'{'h7, 'h7, 'h7, 'h7}");
        clk = 1'b1;  // The only edge
        #1;
        `checkp(row, "'{'hb, 'hc, 'hd, 'he}");
        `checkp(row_nba, "'{'h15, 'h16, 'h17, 'h18}");
        `checkp(row_dly, "'{'hb, 'hc, 'hd, 'he}");
      end
    join
    joined = 1'b1;
  end

  initial begin
    #10;
    if (!joined) `stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
