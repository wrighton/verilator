// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Empty arguments after the leading argument (IEEE 1800-2023 21.2.1, A.8.2 list_of_arguments)
module t;
  localparam int STDOUT = 32'h8000_0001;

  // Elaboration-time severity tasks
  if (0) begin : g_never
    $info(, "never");
    $warning(, "never");
    $error(, "never");
    $fatal(1, , "never");
    $fatal(1, );
  end

  int cyc = 0;
  logic [5:0] v = 6'h2a;
  string s;

  initial begin
    v = v + 6'(cyc);  // Not constant
    $fwrite(STDOUT, , "fwrite", , "%0d\n", 1);
    $fwriteb(STDOUT, , v, "\n");
    $fwriteh(STDOUT, , v, "\n");
    $fwriteo(STDOUT, , v, "\n");
    $fwriteb(STDOUT);
    $fwrite(STDOUT, , );
    $fdisplay(STDOUT, , "fdisplay");
    $fdisplayb(STDOUT, , v);
    $fdisplayh(STDOUT, , v);
    $fdisplayo(STDOUT, , v);
    $fstrobe(STDOUT, , "fstrobe");
    $fstrobeb(STDOUT, , v);
    $fstrobeh(STDOUT, , v);
    $fstrobeo(STDOUT, , v);
    // Only the last $fmonitor is active
    $fmonitor(STDOUT, , "fmonitor");
    $fmonitorb(STDOUT, , v);
    $fmonitorh(STDOUT, , v);
    $fmonitoro(STDOUT, , "fmonitoro ", v);

    $swrite(s, , "a", , "b");
    `checks(s, "a b");
    $swriteb(s, , v);
    `checks(s, "101010");
    $swriteh(s, , v);
    `checks(s, "2a");
    $swriteo(s, , v);
    `checks(s, "52");
    $swrite(s);
    `checks(s, "");

    if (v == 0) $fatal(1, , "never");
    if (v == 0) $fatal(1, );
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
