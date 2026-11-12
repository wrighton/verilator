// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Wide random values must come out well spread, with few solver checks (the .py counts them)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=[%0d:%0d]\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// Array elements tied to another rand array; same constraints on every call
class Tied;
  rand bit [1023:0] a[2];
  rand bit [1023:0] b[2];
  constraint c_tied {foreach (a[i]) a[i] == b[i];}
endclass

// Wide values partly constrained, or behind a guard that is off
class Partial;
  rand bit [127:0] addr;
  rand bit en;
  rand bit [127:0] v;
  constraint c_align {addr[5:0] == 0;}
  constraint c_off {
    en -> $countones(v) == 1;
    !en;
  }
endclass

// Phased solve: the last layer is spread as well
class Ordered;
  rand bit [3:0] x;
  rand bit [127:0] y;
  constraint c_order {solve x before y;}
  constraint c_low {y[3:0] == x;}
endclass

// Wide data with a constrained field in every quarter: the other bits are spread
class Header;
  rand bit [1023:0] d;
  rand bit [7:0] op;
  constraint c_hdr {
    d[7:0] == op;
    op inside {[1 : 3]};
    d[1023:1016] == 8'ha5;
    d[519:512] < 8'd4;
    d[263:256] == 8'h3c;
  }
endclass

// Many bounded elements: spreading them all takes more checks than one call may spend
class Many;
  rand bit [31:0] q[80];
  constraint c_bound {foreach (q[i]) q[i] < 1000;}
endclass

// Wide data picked among constants, with a soft constraint (no UniGen2): spreading it
// must stay cheap, as random parts of it never fit (the .py counts the solver checks)
class Picked;
  rand bit [1:0] sel;
  rand bit [1023:0] d;
  constraint c_pick {
    if (sel == 0) d == 1024'h74bf20f876ffc474c0251908fcdce4b314f68d9dcbd7a085a368932ff2b2d409dd311ca871902316d9841aab4ccec38d79d89a0da0c41aebb8f010b8e9a5b5ab89c3049787a5d33aa7e52a6e87316a58a2b4d98ebd9dd1d460fd71e9a72937116d10f35970d13a48f1b763357840fc1878d1fa0141312f12fa5a2bcc9b86ad34;
    else if (sel == 1) d == 1024'h0c251bec1d1bfadde07682d7d40ab83e3c3a30f47c123c50a303f99217331a52757ec8bcbd2c7d5df4c453ffe54864a79d86908fc65b7af4df6e0f2c1e77268768451851a5d2232891bea00aadcf26fc4a382d3e83bbe983a3fb19545be334ad95ef95235cb388c141f87bace2bf34833356dc44c65568b90edca9f9f06037f5;
    else d inside {1024'he6661e3944e210b72f0aaab4212a626d7fa31d265cff2d6f90eece5e18bbebc7068b4e65605c50435ef510cead117c1cf0773cf65a3b3198e9f780aba21d20302051f16a6fafb1c9c295d3cac5cb5bde7efb85cf1450e23a711eeab026c3a93e267144037967da6e5213036823ec73fbce39ec630e92ab6f2bd267b1a7de286a, 1024'h566edb6dfdf190530491f1668fd1be6943e9de264f9cb5d9ef7b990ebb97004405106ebb1f5708da13e987fd8a10d1574da480510f1eedb595243dbee88e94a41df7e80a3f4883d2b1fe69b5cca1861aac914d8d2f76233092d8fe89157f5445ec04c1559644146c3dc508343494cb260b4f72bf3af0bede9e4ec69595a86411};
  }
  constraint c_soft {soft sel == 2;}
endclass

module t;
  initial begin
    automatic Tied tied = new;
    automatic Partial partial;
    automatic Ordered ordered;
    automatic Picked picked = new;
    automatic Header header = new;
    automatic Many many = new;
    automatic int randomize_result;
    for (int i = 0; i < 8; ++i) begin
      // First, so it is the solver's first transaction (z3 keeps options across reset)
      ordered = new;
      randomize_result = ordered.randomize();
      `checkd(randomize_result, 1);
      `checkd(ordered.y[3:0], ordered.x);
      `check_range($countones(ordered.y[127:4]), 30, 94);
      randomize_result = tied.randomize();
      `checkd(randomize_result, 1);
      foreach (tied.a[j]) begin
        `checkd(tied.a[j], tied.b[j]);
        // 1024 uniform bits: mean 512, standard deviation 16
        `check_range($countones(tied.a[j]), 400, 624);
      end
      // A new object, so its first randomize() each time
      partial = new;
      randomize_result = partial.randomize();
      `checkd(randomize_result, 1);
      `checkd(partial.addr[5:0], 6'd0);
      `checkd(partial.en, 1'b0);
      // 122 and 128 uniform bits: standard deviation under 6
      `check_range($countones(partial.addr), 30, 92);
      `check_range($countones(partial.v), 32, 96);
      randomize_result = header.randomize();
      `checkd(randomize_result, 1);
      `checkd(header.d[7:0], header.op);
      `checkd(header.d[1023:1016], 8'ha5);
      if (header.d[519:512] > 3) `stop;
      `checkd(header.d[263:256], 8'h3c);
      // 992 uniform bits: mean 496, standard deviation 16
      `check_range($countones({header.d[1015:520], header.d[511:264], header.d[255:8]}), 384, 608);
      randomize_result = picked.randomize();
      `checkd(randomize_result, 1);
      `checkd(picked.sel, 2'd2);
    end
    // Last, after the solve...before case had the solver's first transaction
    randomize_result = many.randomize();
    `checkd(randomize_result, 1);
    foreach (many.q[i]) if (many.q[i] >= 1000) `stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
