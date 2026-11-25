// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Transactions passed through a bounded mailbox at time zero; at most a few are live at once,
// so memory use must not grow with the number sent

class Txn;
  int data[4095];
endclass

module t;
  localparam int COUNT = 2000;

  mailbox #(Txn) mb = new(4);
  int sum = 0;

  initial begin
    fork
      for (int i = 0; i < COUNT; ++i) begin
        automatic Txn tx = new;
        tx.data[4094] = i;
        mb.put(tx);
      end
      for (int i = 0; i < COUNT; ++i) begin
        Txn rx;
        mb.get(rx);
        sum += rx.data[4094];
      end
    join
    `checkd(sum, COUNT * (COUNT - 1) / 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
