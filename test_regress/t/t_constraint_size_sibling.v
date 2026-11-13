// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Sibling classes each constraining the size of an array declared in their base

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Base;
  rand bit [3:0] q[$];
  rand bit [3:0] d[];
  rand int unsigned len;
  constraint c_len { len inside {[1:4]}; }
endclass

class SibA extends Base;
  constraint c_size { q.size() == len; }
endclass

class SibB extends Base;
  constraint c_size { q.size() == 3; d.size() == 2; }
endclass

typedef struct packed { int W; } p_t;
localparam p_t PA = '{W: 4};
localparam p_t PB = '{W: 8};

class PBase #(parameter p_t P = PA);
  rand bit [P.W-1:0] arr[];
  rand int unsigned len;
  constraint c_len { len inside {[1:4]}; }
endclass

class PSibA #(parameter p_t P = PA) extends PBase #(P);
  constraint c_size { arr.size() == len; }
endclass

class PSibB #(parameter p_t P = PB) extends PBase #(P);
  constraint c_size { arr.size() == 0; }
endclass

module t;
  initial begin
    automatic Base b = new;
    automatic SibA sa = new;
    automatic SibB sb = new;
    automatic PSibA #(PA) pa = new;
    automatic PSibB #(PA) pb = new;
    automatic PSibA #(PB) pa2 = new;
    automatic PSibB #(PB) pb2 = new;
    automatic int randomize_result;

    b.q = '{1, 2};
    repeat (10) begin
      randomize_result = sa.randomize();
      `checkd(randomize_result, 1);
      `checkd(sa.q.size(), sa.len);
      `checkd(sa.d.size(), 0);
      randomize_result = sb.randomize();
      `checkd(randomize_result, 1);
      `checkd(sb.q.size(), 3);
      `checkd(sb.d.size(), 2);
      randomize_result = sb.randomize() with { d.size() == len; };
      `checkd(randomize_result, 1);
      `checkd(sb.q.size(), 3);
      `checkd(sb.len, 2);
      `checkd(sb.d.size(), 2);
      randomize_result = b.randomize();
      `checkd(randomize_result, 1);
      `checkd(b.q.size(), 2);
    end

    pb.arr = '{1, 2};
    pb2.arr = '{1, 2};
    repeat (10) begin
      randomize_result = pa.randomize();
      `checkd(randomize_result, 1);
      `checkd(pa.arr.size(), pa.len);
      randomize_result = pb.randomize();
      `checkd(randomize_result, 1);
      `checkd(pb.arr.size(), 0);
      randomize_result = pa2.randomize();
      `checkd(randomize_result, 1);
      `checkd(pa2.arr.size(), pa2.len);
      randomize_result = pb2.randomize();
      `checkd(randomize_result, 1);
      `checkd(pb2.arr.size(), 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
