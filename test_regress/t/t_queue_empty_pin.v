// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  task tsk(int q[] = {});
    if (q.size != 0) $stop;
  endtask

  task qtsk(int q[$]);
    if (q.size != 0) $stop;
  endtask

  task dtsk(int q[]);
    if (q.size != 0) $stop;
  endtask

  initial begin
    tsk();
    qtsk({});
    dtsk({});

    begin : builtin_method_arg
      typedef int dyn_t[];
      int qq[$][$];
      dyn_t qd[$];
      qq.push_back({});
      qq[0].push_back(5);
      qq.push_front({});
      qq.insert(1, {});
      qd.push_back({});
      `checkd(qq.size(), 3);
      `checkd(qq[0].size(), 0);
      `checkd(qq[1].size(), 0);
      `checkd(qq[2].size(), 1);
      `checkd(qq[2][0], 5);
      `checkd(qd.size(), 1);
      `checkd(qd[0].size(), 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
