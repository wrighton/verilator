// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

module t;

  class branch_item;
    rand bit before_value[4];
    rand int unsigned arr[4];
    rand bit after_value[4];
    rand bit implied_value[4];
    bit sel;

    constraint branches_c {
      foreach (arr[i]) {
        before_value[i] dist {0 := 1, 1 := 3};
        sel -> implied_value[i] dist {0 := 1, 1 := 3};
        if (sel) {
          if ((i % 2) != 0) {
            arr[i] dist {i := 1, (i + 8) := 3};
          } else {
            arr[i] dist {i := 1, (i + 8) := 3};
          }
        } else {
          arr[i] dist {(i + 4) := 3, (i + 12) := 1};
        }
        after_value[i] dist {0 := 1, 1 := 3};
      }
    }
  endclass

  class inline_item;
    rand bit before_value[4];
    rand int unsigned arr[4];
    rand bit after_value[4];
  endclass

  class item;
    rand int unsigned arr[4];
    rand int unsigned wgt_zero;
    rand int unsigned wgt_nonzero;

    constraint wgt_c {
      wgt_zero inside {[1:10]};
      wgt_nonzero inside {[1:10]};
    }

    constraint dist_foreach_c {
      foreach (arr[i]) {
        arr[i] dist {0 :/ wgt_zero, [1:15] :/ wgt_nonzero};
      }
    }
  endclass

  initial begin
    static item it = new;
    int randomize_result;
    repeat (20) begin
      randomize_result = it.randomize();
      `checkd(randomize_result, 1);
      foreach (it.arr[i]) begin
        `checkd(it.arr[i] <= 32'd15, 1);
      end
    end

    begin
      localparam int N = 800;
      automatic branch_item b = new;
      automatic int hits;
      automatic int before_hits;
      automatic int after_hits;
      automatic int implied_hits;
      // Preambles before, inside and after recursive branches all survive.
      for (int select = 0; select < 2; select++) begin
        b.sel = (select != 0);
        hits = 0;
        before_hits = 0;
        after_hits = 0;
        implied_hits = 0;
        repeat (N / 4) begin
          randomize_result = b.randomize();
          `checkd(randomize_result, 1);
          foreach (b.arr[i]) begin
            if (b.sel) begin
              `checkd(b.arr[i] inside {i, (i + 8)}, 1);
              if (b.arr[i] == i + 8) hits++;
            end
            else begin
              `checkd(b.arr[i] inside {(i + 4), (i + 12)}, 1);
              if (b.arr[i] == i + 4) hits++;
            end
            if (b.before_value[i]) before_hits++;
            if (b.after_value[i]) after_hits++;
            if (b.implied_value[i]) implied_hits++;
          end
        end
        `check_range(hits, N * 65 / 100, N * 85 / 100);
        `check_range(before_hits, N * 65 / 100, N * 85 / 100);
        `check_range(after_hits, N * 65 / 100, N * 85 / 100);
        if (b.sel) `check_range(implied_hits, N * 65 / 100, N * 85 / 100);
      end
    end

    begin
      localparam int N = 800;
      automatic inline_item b = new;
      automatic int hits = 0;
      automatic int before_hits = 0;
      automatic int after_hits = 0;
      automatic bit select;
      for (int call_index = 0; call_index < N / 4; call_index++) begin
        select = (call_index % 2 != 0);
        randomize_result = b.randomize() with {
          foreach (arr[i]) {
            before_value[i] dist {0 := 1, 1 := 3};
            if (select) {
              arr[i] dist {i := 1, (i + 8) := 3};
            } else {
              arr[i] dist {(i + 4) := 3, (i + 12) := 1};
            }
            after_value[i] dist {0 := 1, 1 := 3};
          }
        };
        `checkd(randomize_result, 1);
        foreach (b.arr[i]) begin
          if (select) begin
            `checkd(b.arr[i] inside {i, (i + 8)}, 1);
            if (b.arr[i] == i + 8) hits++;
          end
          else begin
            `checkd(b.arr[i] inside {(i + 4), (i + 12)}, 1);
            if (b.arr[i] == i + 4) hits++;
          end
          if (b.before_value[i]) before_hits++;
          if (b.after_value[i]) after_hits++;
        end
      end
      `check_range(hits, N * 65 / 100, N * 85 / 100);
      `check_range(before_hits, N * 65 / 100, N * 85 / 100);
      `check_range(after_hits, N * 65 / 100, N * 85 / 100);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
