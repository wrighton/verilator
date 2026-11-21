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

class DistScalar;
  rand bit [7:0] x;
  constraint c {
    x dist {
      8'd0 := 1,
      8'd255 := 3
    };
  }
endclass

class DistRange;
  rand bit [7:0] x;
  constraint c {
    x dist {
      [8'd0 : 8'd9] :/ 1,
      [8'd10 : 8'd19] :/ 3
    };
  }
endclass

class DistZeroWeight;
  rand bit [7:0] x;
  constraint c {
    x dist {
      8'd0 := 0,
      8'd1 := 1,
      8'd2 := 1
    };
  }
endclass

class DistAllZeroWeight;
  rand bit [7:0] x;
  constraint c {
    x dist {
      8'd0 := 0,
      8'd1 := 0,
      8'd2 := 0
    };
  }
endclass

class DistVarWeight;
  rand bit [7:0] x;
  int w1, w2;
  constraint c {
    x dist {
      8'd0 := w1,
      8'd255 := w2
    };
  }
endclass

class DistVarWeightRange;
  rand bit [7:0] x;
  int w1, w2;
  constraint c {
    x dist {
      [8'd0 : 8'd9] :/ w1,
      [8'd10 : 8'd19] :/ w2
    };
  }
endclass

// A weight of zero is a constraint (IEEE 1800-2023 18.5.3), also when only known at runtime
class DistVarZeroWeight;
  rand bit [7:0] x;
  int w0, w1;
  constraint c {
    x dist {
      8'd0 := w0,
      [8'd1 : 8'd15] :/ w1,
      8'd16 := 1
    };
  }
endclass

// A random weight is solved together with the value
class DistRandWeight;
  rand bit [7:0] x;
  rand bit [2:0] w;
  constraint c {
    x dist {
      8'd0 := w,
      8'd1 := 1
    };
  }
endclass

// A runtime weight per foreach element
class DistForeachZeroWeight;
  rand bit [3:0] a[3];
  int wts[3];
  constraint c {
    foreach (a[i]) {
      a[i] dist {
        0 := wts[i],
        [1 : 15] :/ 1
      };
    }
  }
endclass

class DistVarWeightWithExclusion;
  rand bit [7:0] x;
  constraint c {
    x dist {
      8'd13 := 10,
      8'd10 := 2
    };
  }
  constraint excl {x != 8'd13;}
endclass

module t;
  initial begin
    DistScalar sc;
    DistRange rg;
    DistZeroWeight zw;
    DistAllZeroWeight azw;
    DistVarWeight vw;
    DistVarWeightRange vwr;
    DistVarWeightWithExclusion vwwe;
    int count_high;
    int count_range_high;
    int total;
    int randomize_result;

    total = 2000;

    // := scalar weights: expect ~75% for value 255
    sc = new;
    count_high = 0;
    repeat (total) begin
      randomize_result = sc.randomize();
      `checkd(randomize_result, 1);
      if (sc.x == 8'd255) count_high++;
      else `checkd(sc.x, 0);
    end
    `check_range(count_high, total * 60 / 100, total * 90 / 100);

    // :/ range weights: expect ~75% in [10:19]
    rg = new;
    count_range_high = 0;
    repeat (total) begin
      randomize_result = rg.randomize();
      `checkd(randomize_result, 1);
      if (rg.x >= 8'd10 && rg.x <= 8'd19) count_range_high++;
      else if (rg.x > 8'd9) begin
        $write("%%Error: x=%0d outside valid range [0:19]\n", rg.x);
        `stop;
      end
    end
    `check_range(count_range_high, total * 60 / 100, total * 90 / 100);

    // Zero weight: value 0 must never appear
    zw = new;
    repeat (total) begin
      randomize_result = zw.randomize();
      `checkd(randomize_result, 1);
      if (zw.x == 8'd0) begin
        $write("%%Error: zero-weight value 0 was selected\n");
        `stop;
      end
      `check_range(zw.x, 1, 2);
    end

    // All-zero weights: dist constraint is effectively unconstrained, randomize succeeds
    azw = new;
    repeat (20) begin
      randomize_result = azw.randomize();
      `checkd(randomize_result, 1);
    end

    // Variable := scalar weights: w1=1, w2=3 => expect ~75% for value 255
    vw = new;
    vw.w1 = 1;
    vw.w2 = 3;
    count_high = 0;
    repeat (total) begin
      randomize_result = vw.randomize();
      `checkd(randomize_result, 1);
      if (vw.x == 8'd255) count_high++;
      else `checkd(vw.x, 0);
    end
    `check_range(count_high, total * 60 / 100, total * 90 / 100);

    // Variable :/ range weights: w1=1, w2=3 => expect ~75% in [10:19]
    vwr = new;
    vwr.w1 = 1;
    vwr.w2 = 3;
    count_range_high = 0;
    repeat (total) begin
      randomize_result = vwr.randomize();
      `checkd(randomize_result, 1);
      if (vwr.x >= 8'd10 && vwr.x <= 8'd19) count_range_high++;
      else if (vwr.x > 8'd9) begin
        $write("%%Error: x=%0d outside valid range [0:19]\n", vwr.x);
        `stop;
      end
    end
    `check_range(count_range_high, total * 60 / 100, total * 90 / 100);

    begin
      DistVarZeroWeight vzw;
      vzw = new;
      vzw.w0 = 0;
      vzw.w1 = 1;
      randomize_result = vzw.randomize() with {x == 0;};
      `checkd(randomize_result, 0);
      repeat (20) begin
        randomize_result = vzw.randomize() with {x < 16;};
        `checkd(randomize_result, 1);
        `check_range(vzw.x, 1, 15);
      end
      vzw.w0 = 1;
      vzw.w1 = 0;
      randomize_result = vzw.randomize() with {x inside {[1 : 15]};};
      `checkd(randomize_result, 0);
      repeat (20) begin
        randomize_result = vzw.randomize() with {x < 16;};
        `checkd(randomize_result, 1);
        `checkd(vzw.x, 0);
      end
    end

    // All weights zero at runtime: no value is allowed
    vw.w1 = 0;
    vw.w2 = 0;
    randomize_result = vw.randomize();
    `checkd(randomize_result, 0);

    begin
      DistForeachZeroWeight dfz;
      dfz = new;
      dfz.wts = '{0, 1, 0};
      randomize_result = dfz.randomize() with {a[0] == 0;};
      `checkd(randomize_result, 0);
      randomize_result = dfz.randomize() with {a[1] == 0;};
      `checkd(randomize_result, 1);
      `checkd(dfz.a[1], 0);
      `check_range(dfz.a[0], 1, 15);
      `check_range(dfz.a[2], 1, 15);
    end

    begin
      DistRandWeight drw;
      drw = new;
      repeat (20) begin
        randomize_result = drw.randomize() with {x == 0;};
        `checkd(randomize_result, 1);
        `check_range(drw.w, 1, 7);
      end
      randomize_result = drw.randomize() with {x == 0; w == 0;};
      `checkd(randomize_result, 0);
    end

    vwwe = new;
    repeat (total) begin
      randomize_result = vwwe.randomize();
      `checkd(randomize_result, 1);
      `checkd(vwwe.x, 8'd10);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
