// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A solver that exits while spreading a solution leaves randomize() returning the solution
// found, which satisfies the constraints; one that exits while answering the model leaves
// randomize() returning 0 with the variables as they were

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Packet;
  rand bit [7:0] a;
  rand bit [7:0] b;
  constraint c {
    a > 8'd10;
    b < 8'd200;
    a != b;
  }
endclass

// Solved in two phases, a and then b, each spread; arrays keep the phases from being
// sampled instead
class Phased;
  rand bit [3:0] a[2];
  rand bit [3:0] b[2];
  constraint order_c {solve a before b;}
  constraint rel_c {foreach (b[i]) b[i] > a[i];}
endclass

// Its randc variable keeps UniGen2 from sampling, so each call spreads its solution
class Spread;
  rand bit [7:0] a;
  randc bit [3:0] r;
  constraint c {
    a > 8'd10;
    r != 4'd15;
  }
endclass

// Sampled by UniGen2 from its second call on; relating two elements keeps the array from
// being sampled natively, one element at a time
class Sampled;
  rand bit [7:0] v[4];
  constraint c {
    foreach (v[i]) v[i] > 8'd10;
    v[0] != v[1];
  }
endclass

module t;
  initial begin
    automatic Packet p = new;
    automatic Phased ph = new;
    automatic Spread wd = new;
    automatic Sampled sm = new;
    automatic int npass = 0;
    automatic int rc;
    automatic int calls = 4;
    bit seen[bit [7:0]];  // Values of wd.a after the first call
    void'($value$plusargs("calls=%d", calls));
    for (int i = 0; i < calls; ++i) begin
      if ($test$plusargs("phased")) begin
        ph.b = '{4'd0, 4'd0};
        rc = ph.randomize();
        if (rc != 0) begin
          npass++;
          if (ph.b[0] <= ph.a[0] || ph.b[1] <= ph.a[1]) begin
            $write("%%Error: %s:%0d:  a=%p b=%p break the constraints\n", `__FILE__,
                   `__LINE__, ph.a, ph.b);
            `stop;
          end
        end else begin
          `checkd(ph.b[0], 4'd0);
          `checkd(ph.b[1], 4'd0);
        end
        continue;
      end
      if ($test$plusargs("sampled")) begin
        rc = sm.randomize();
        if (rc != 0) begin
          npass++;
          foreach (sm.v[k]) begin
            if (sm.v[k] <= 8'd10) begin
              $write("%%Error: %s:%0d:  v[%0d]=%0d breaks the constraint\n", `__FILE__,
                     `__LINE__, k, sm.v[k]);
              `stop;
            end
          end
        end
        continue;
      end
      if ($test$plusargs("wide")) begin
        wd.a = 8'd5;
        rc = wd.randomize();
        if (rc != 0) begin
          npass++;
          if (wd.a <= 8'd10) begin
            $write("%%Error: %s:%0d:  a=%0d breaks the constraint\n", `__FILE__, `__LINE__,
                   wd.a);
            `stop;
          end
          if (i != 0) seen[wd.a] = 1'b1;
        end else begin
          `checkd(wd.a, 8'd5);
        end
        continue;
      end
      // Outside the constraints, so any model the runtime applies overwrites them
      p.a = 8'd5;
      p.b = 8'd250;
      rc = p.randomize();
      if (rc != 0) begin
        npass++;
        if (p.a <= 8'd10 || p.b >= 8'd200 || p.a == p.b) begin
          $write("%%Error: %s:%0d:  a=%0d b=%0d break the constraints\n", `__FILE__, `__LINE__,
                 p.a, p.b);
          `stop;
        end
      end else begin
        `checkd(p.a, 8'd5);
        `checkd(p.b, 8'd250);
      end
    end
    // A copy spreads afresh, whatever its original's pause
    if ($test$plusargs("copy")) begin
      automatic Spread wc = new wd;
      rc = wc.randomize();
      if (rc != 0) npass++;
    end
    $write("NPASS=%0d\n", npass);
    $write("DISTINCT=%0d\n", seen.num());
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
