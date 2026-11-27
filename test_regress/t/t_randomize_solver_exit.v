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

module t;
  initial begin
    automatic Packet p = new;
    automatic Phased ph = new;
    automatic int npass = 0;
    automatic int rc;
    for (int i = 0; i < 4; ++i) begin
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
    $write("NPASS=%0d\n", npass);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
