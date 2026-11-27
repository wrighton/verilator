// DESCRIPTION: Verilator: Deterministic independent DIST diagnostics
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); `stop; end while (0);
`define ITEM_TEN(b, n, w) \
  b'(n+0) := w, b'(n+1) := w, b'(n+2) := w, b'(n+3) := w, b'(n+4) := w, \
  b'(n+5) := w, b'(n+6) := w, b'(n+7) := w, b'(n+8) := w, b'(n+9) := w
`define ITEM_FIFTY(b, n, w) \
  `ITEM_TEN(b, n, w), `ITEM_TEN(b, n+10, w), `ITEM_TEN(b, n+20, w), `ITEM_TEN(b, n+30, w), \
  `ITEM_TEN(b, n+40, w)
// verilog_format: on

module t;
  import "DPI-C" function byte dist_endpoint(input byte x);

  class MembershipOnly;
    rand byte x;
    byte endpoint = 1;
    bit enabled;
    constraint c {
      if (enabled) x dist {dist_endpoint(endpoint) := 1, 8'd2 := 0};
    }
  endclass

  // Rejecting many heavy buckets cuts the first draw only; the others keep their weights.
  class ManyDraws;
    rand bit [8:0] first, first_offset;
    rand bit [2:0] values[4];
    rand bit [2:0] offset, dropped, retained, pick;
    bit [1023:0] weight = 1;
    constraint c {
      first == 9'd0;
      first_offset == 9'd0;
      offset == 0;
      dropped == 5;
      (first + first_offset) dist {
        `ITEM_FIFTY(9, 1, 16'hffff), `ITEM_FIFTY(9, 51, 16'hffff), `ITEM_FIFTY(9, 101, 16'hffff),
        `ITEM_FIFTY(9, 151, 16'hffff), `ITEM_FIFTY(9, 201, 16'hffff), `ITEM_FIFTY(9, 251, 16'hffff),
        9'd0 := 16'd1
      };
      foreach (values[i]) (values[i] + offset) dist {[3'd1:3'd7] :/ weight};
      soft (dropped + offset) dist {3'd3 := 1};
      soft (retained + offset) dist {3'd5 := 1};
      (pick + offset) dist {3'd2 := 1, 3'd6 := 9};
    }
  endclass

  // Rejecting many heavy buckets uses up the work for choosing another.
  class ChoiceWork;
    rand bit [8:0] pick, offset;
    constraint c {
      pick == 9'd0;
      offset == 0;
      (pick + offset) dist {
        `ITEM_FIFTY(9, 1, 16'hffff), `ITEM_FIFTY(9, 51, 16'hffff), `ITEM_FIFTY(9, 101, 16'hffff),
        `ITEM_FIFTY(9, 151, 16'hffff), `ITEM_FIFTY(9, 201, 16'hffff), `ITEM_FIFTY(9, 251, 16'hffff),
        9'd0 := 16'd1
      };
    }
  endclass

  // Rejecting many heavy buckets leaves too few checks for the sparse range's points.
  class PointChecks;
    rand bit [9:0] pick, offset;
    constraint c {
      pick == 10'd7;
      offset == 0;
      (pick + offset) dist {
        `ITEM_FIFTY(10, 256, 12'hfff), `ITEM_FIFTY(10, 306, 12'hfff),
        `ITEM_FIFTY(10, 356, 12'hfff), `ITEM_FIFTY(10, 406, 12'hfff),
        `ITEM_FIFTY(10, 456, 12'hfff), `ITEM_TEN(10, 506, 12'hfff), [10'd0:10'd255] :/ 1
      };
    }
  endclass

  // Each heavy bucket rejection leaves fewer checks for spreading the other values.
  class SpreadChecks;
    rand bit [8:0] pick, offset;
    rand bit flags[16];
    constraint c {
      pick == 9'd0;
      offset == 0;
      foreach (flags[i]) flags[i] == 1'b1;
      (pick + offset) dist {
        `ITEM_FIFTY(9, 1, 12'hfff), `ITEM_FIFTY(9, 51, 12'hfff), `ITEM_FIFTY(9, 101, 12'hfff),
        `ITEM_FIFTY(9, 151, 12'hfff), `ITEM_FIFTY(9, 201, 12'hfff), 9'd251 := 12'hfff,
        9'd252 := 12'hfff, `ITEM_TEN(9, 253, 12'hfff), 9'd0 := 12'd1
      };
    }
  endclass

  // Spreading many constrained wide values ends with a failed check after a batch.
  class BatchRestore;
    rand bit [1023:0] w0, w1, w2, w3, w4, w5;
    rand bit [3:0] pick, second, offset;
    bit [1023:0] mask = {64{16'h8001}};
    constraint c {
      offset == 0;
      (w0 & mask) == (mask & {64{16'h0001}});
      (w1 & mask) == (mask & {64{16'h8000}});
      (w2 & mask) == mask;
      (w3 & mask) == '0;
      (w4 & mask) == mask;
      (w5 & mask) == '0;
      (second + offset) dist {4'd5 := 2, 4'd9 := 1};
      (pick + offset) dist {4'd3 := 1, 4'd7 := 2};
    }
  endclass

  // A batch clamps each range to its only representable point.
  class SingletonClamp;
    rand bit [3:0] a[4];
    rand bit signed [7:0] b[4];
    constraint c {
      foreach (a[i]) a[i] dist {[15:22] :/ 1};
      foreach (b[i]) b[i] dist {[-200:-128] :/ 1};
    }
  endclass

  // Two draws that reject many heavy buckets still leave the last one its first draw.
  class TailDraw;
    rand bit [8:0] a, b, z, offset;
    constraint c {
      a == 9'd0;
      b == 9'd0;
      offset == 0;
      (a + offset) dist {
        `ITEM_FIFTY(9, 1, 12'hfff), `ITEM_FIFTY(9, 51, 12'hfff), `ITEM_FIFTY(9, 101, 12'hfff),
        `ITEM_FIFTY(9, 151, 12'hfff), `ITEM_FIFTY(9, 201, 12'hfff), `ITEM_TEN(9, 251, 12'hfff),
        `ITEM_TEN(9, 261, 12'hfff), 9'd0 := 12'd1
      };
      (b + offset) dist {
        `ITEM_FIFTY(9, 1, 12'hfff), `ITEM_FIFTY(9, 51, 12'hfff), `ITEM_FIFTY(9, 101, 12'hfff),
        `ITEM_FIFTY(9, 151, 12'hfff), `ITEM_FIFTY(9, 201, 12'hfff), `ITEM_TEN(9, 251, 12'hfff),
        `ITEM_TEN(9, 261, 12'hfff), 9'd0 := 12'd1
      };
      (z + offset) dist {9'd1 := 12'hfff, 9'd2 := 12'd1};
    }
  endclass

  initial begin
    begin
      automatic MembershipOnly obj = new;
      int ok;
      bit saw_other;
      obj.enabled = 0;
      saw_other = 0;
      repeat (16) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        saw_other |= obj.x != 1;
      end
      `checkd(saw_other, 1'b1);
      $display("Inactive constraint checked");
      obj.enabled = 1;
      obj.x = 1;
      ok = obj.randomize(null);
      `checkd(ok, 1);
      $display("Check-only constraint checked");
      repeat (2) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd(obj.x, 1);
      end
      $display("Active constraint checked");
    end
    begin
      automatic ManyDraws obj = new;
      int ok;
      obj.srandom(215);
      $display("Many-draw admission check");
      for (int call = 0; call < 2; ++call) begin
        if (call == 0) ok = obj.randomize();
        else ok = obj.randomize() with {disable soft dropped;};
        `checkd(ok, 1);
        `checkd(obj.first, 9'd0);
        foreach (obj.values[i]) `checkd(obj.values[i] != 0, 1'b1);
        `checkd(obj.dropped, 3'd5);
        `checkd(obj.retained, 3'd5);
        `checkd((obj.pick inside {3'd2, 3'd6}), 1'b1);
      end
      $display("Many-draw satisfying models retained");
      begin
        int heavy;
        heavy = 0;
        repeat (32) begin
          ok = obj.randomize();
          `checkd(ok, 1);
          heavy += int'(obj.pick == 3'd6);
        end
        // pick follows its 1:9 weights after the first draw is cut (expected 28.8 of 32).
        `checkd((heavy >= 22), 1'b1);
      end
    end
    begin
      automatic TailDraw obj = new;
      int heavy, ok;
      heavy = 0;
      obj.srandom(217);
      $display("Tail draw after cut draws");
      repeat (16) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.z inside {9'd1, 9'd2}), 1'b1);
        heavy += int'(obj.z == 9'd1);
      end
      // z keeps its 4095:1 weights (expected 16 of 16).
      `checkd((heavy >= 15), 1'b1);
    end
    begin
      automatic ChoiceWork choice = new;
      automatic PointChecks point = new;
      int ok;
      choice.srandom(17);
      point.srandom(19);
      $display("Rejected bucket checks");
      ok = choice.randomize();
      `checkd(ok, 1);
      `checkd(choice.pick, 9'd0);
      ok = point.randomize();
      `checkd(ok, 1);
      `checkd(point.pick, 10'd7);
    end
    begin
      automatic SpreadChecks obj = new;
      int ok;
      obj.srandom(23);
      $display("Spreading after rejected buckets");
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.pick, 9'd0);
      foreach (obj.flags[i]) `checkd(obj.flags[i], 1'b1);
    end
    begin
      automatic BatchRestore obj = new;
      int ok;
      obj.srandom(311);
      $display("Batch restored after spreading");
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(((obj.w2 & obj.mask) == obj.mask), 1'b1);
      `checkd(((obj.w5 & obj.mask) == '0), 1'b1);
      `checkd((obj.pick inside {4'd3, 4'd7}), 1'b1);
      `checkd((obj.second inside {4'd5, 4'd9}), 1'b1);
    end
    begin
      automatic SingletonClamp obj = new;
      int ok;
      $display("Singleton clamp check");
      ok = obj.randomize();
      `checkd(ok, 1);
      foreach (obj.a[i]) `checkd(obj.a[i], 4'd15);
      foreach (obj.b[i]) `checkd(obj.b[i], -8'sd128);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
