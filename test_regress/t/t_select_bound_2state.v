// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // Positions known only at run time, above the vectors below
  int pos[] = '{6, 7};

  initial begin
    foreach (pos[n]) void'($value$plusargs($sformatf("pos%0d=%%d", n), pos[n]));

    begin
      // Test: out-of-range bits of a 2-state vector read as zero (IEEE 1800-2023 11.5.1)
      bit [5:0] v;
      bit [94:0] w;
      v = '1;
      w = '1;
      foreach (pos[n]) begin
        `checkh(v[pos[n]], 1'b0);
        `checkh(w[pos[n] + 100], 1'b0);
        `checkh(w[pos[n] + 100+:40], 40'h0);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
