// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Zero-time infinite loops, selected by plusarg, that never converge

module t (  /*AUTOARG*/
  // Outputs
  a, b
  );

  // +mailbox: a producer and a consumer exchange items forever at time 0
  mailbox #(int) mb = new(1);
  initial begin
    if ($test$plusargs("mailbox")) begin
      fork
        forever mb.put(1);
        begin
          int v;
          forever mb.get(v);
        end
      join
    end
  end

  // +event: two processes trigger each other forever at time 1
  event e1, e2;
  initial begin
    if ($test$plusargs("event")) begin
      fork
        forever begin
          @(e1);
          ->e2;
        end
        begin
          #1;
          forever begin
            ->e1;
            @(e2);
          end
        end
      join
    end
  end

  // +comb: combinational feedback with an odd inversion oscillates
  // verilator lint_off UNOPTFLAT
  output logic a, b;
  logic en = 1'b0;
  initial en = $test$plusargs("comb");
  always_comb b = ~a & en;
  always_comb a = b;
  // verilator lint_on UNOPTFLAT

  // +nba: nonblocking assignments keep retriggering a process at time 1
  logic t = 1'b0;
  initial begin
    if ($test$plusargs("nba")) begin
      #1 t = 1'b1;
    end
  end
  always @(t) t <= ~t;

  initial begin
    #2;
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
