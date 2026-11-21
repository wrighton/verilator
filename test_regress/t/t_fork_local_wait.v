// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // Event controls in forked processes on expressions of variables local to each process
  int finished = 0;

  initial begin
    bit done[3];
    int cnt;
    cnt = 0;
    fork
      automatic int j = 1;
      begin
        wait (done[j]);
        cnt++;
      end
    join_none
    #1 done[1] = 1;
    #1 `checkd(cnt, 1);
    ++finished;
  end

  bit flag[5];
  initial begin
    bit [4:0] woke;
    woke = '0;
    for (int i = 0; i < 5; i++) begin
      fork
        automatic int j = i;
        begin
          @(posedge flag[j]);
          woke[j] = 1'b1;
        end
      join_none
    end
    for (int i = 4; i >= 0; i--) begin
      #1 flag[i] = 1;
      #1 `checkh(woke, 5'(5'h1f << i));
    end
    ++finished;
  end

  int sel = -1;
  int seen[$];
  task automatic wait_sel(int j);
    wait (sel == j);
    seen.push_back(j);
  endtask
  initial begin
    for (int i = 0; i < 3; i++) begin
      fork
        automatic int j = i;
        wait_sel(j);
      join_none
    end
    #1 sel = 2;
    #1 sel = 0;
    #1 sel = 1;
    #1 `checkd(seen.size(), 3);
    `checkd(seen[0], 2);
    `checkd(seen[1], 0);
    `checkd(seen[2], 1);
    ++finished;
  end

  // A single process waiting through an automatic loop index keeps a static trigger
  bit go[3];
  initial begin
    int order[$];
    for (int i = 2; i >= 0; i--) begin
      wait (go[i]);
      order.push_back(i);
    end
    `checkd(order.size(), 3);
    `checkd(order[2], 0);
    ++finished;
  end
  initial begin
    #1 go[0] = 1;
    #1 go[2] = 1;
    #1 go[1] = 1;
  end

  initial begin
    wait (finished == 4);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
