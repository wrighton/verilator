// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// verilator lint_off WIDTH
// verilator lint_off UNSIGNED
// verilator lint_off CMPCONST
module t;

  int calls = 0;
  function automatic bit signed [7:0] next_value(input bit signed [7:0] value);
    ++calls;
    return value;
  endfunction
  function automatic bit signed [2:0] next_small(input bit signed [2:0] value);
    ++calls;
    return value;
  endfunction
  function automatic bit [3:0] next_nibble(input bit [3:0] value);
    ++calls;
    return value;
  endfunction
  function automatic real next_real(input real value);
    ++calls;
    return value;
  endfunction
  int other_calls = 0;
  function automatic bit [3:0] other_nibble();
    ++other_calls;
    return 0;
  endfunction

  initial begin
    begin
      // Signed expression with unsigned bounds compares unsigned
      bit signed [7:0] v;
      bit signed [7:0] x;
      v = -5;
      `checkd(v inside {[9'd0 : 9'd300]}, 1'b1);
      `checkd(!(v inside {[9'd0 : 9'd300]}), 1'b0);
      `checkd(v inside {[9'd0 : 9'd250]}, 1'b0);
      `checkd(v inside {[$ : 9'd300]}, 1'b1);
      `checkd(v inside {[9'd252 : $]}, 1'b0);
      `checkd(v inside {[-8'sd3 : $]}, 1'b0);
      `checkd(v inside {[-8'sd10 : 8'sd10], 9'd300}, 1'b1);
      `checkd((v + 8'sd0) inside {[9'd0 : 9'd300]}, 1'b1);
      x = -11;
      `checkd(x inside {9'd245}, 1'b1);
      `checkd(x inside {8'sd245}, 1'b1);
      `checkd(x inside {-9'sd11}, 1'b1);
      if (x inside {[-3 : 3]}) `stop;
      if (!(x inside {[-11 : -11]})) `stop;
    end
    begin
      // Every value against items and bounds of each signedness and width
      bit signed [3:0] s;
      bit [3:0] u;
      for (int i = 0; i < 16; ++i) begin
        s = 4'(i);
        u = 4'(i);
        `checkd(s inside {3'd5}, s == 3'd5);
        `checkd(s inside {4'd11}, s == 4'd11);
        `checkd(s inside {5'd27}, s == 5'd27);
        `checkd(s inside {-3'sd2}, s == -3'sd2);
        `checkd(s inside {-5'sd7}, s == -5'sd7);
        `checkd(s inside {[3'd1 : 3'd6]}, s >= 3'd1 && s <= 3'd6);
        `checkd(s inside {[4'd2 : 4'd13]}, s >= 4'd2 && s <= 4'd13);
        `checkd(s inside {[5'd3 : 5'd20]}, s >= 5'd3 && s <= 5'd20);
        `checkd(s inside {[-5'sd6 : 5'sd4]}, s >= -5'sd6 && s <= 5'sd4);
        `checkd(s inside {[-3 : 9'd300]}, s >= -3 && s <= 9'd300);
        `checkd(s inside {[3'd2 : -2'sd1]}, s >= 3'd2 && s <= -2'sd1);
        `checkd(s inside {[-8'sd6 : -8'sd2], 6'd9}, (s >= -8'sd6 && s <= -8'sd2) || s == 6'd9);
        `checkd(u inside {-3'sd2}, u == -3'sd2);
        `checkd(u inside {-5'sd7}, u == -5'sd7);
        `checkd(u inside {[-5'sd6 : 5'sd4]}, u >= -5'sd6 && u <= 5'sd4);
        `checkd(u inside {[2'sd1 : 5'sd20]}, u >= 2'sd1 && u <= 5'sd20);
        `checkd(u inside {[-8'sd3 : $]}, u >= -8'sd3);
      end
    end
    begin
      // Wildcard items; x and z bits of the expression are not do-not-care
      logic signed [3:0] l;
      l = 4'sb1011;
      `checkd(l inside {5'b1x011}, 1'b0);
      `checkd(l inside {5'b0x011}, 1'b1);
      `checkd(l inside {5'sb1x011}, 1'b1);
      `checkd(l inside {5'b0?0?1}, 1'b1);
      l = 4'sbx011;
      `checkd(l inside {5'b0z011}, 1'b1);
      `checkd(l inside {5'b1z011}, 1'b0);
    end
    begin
      // Elements of unpacked arrays compare as single items
      bit signed [7:0] v;
      bit [8:0] w;
      shortint h;
      bit [8:0] q[$];
      byte fixed[2];
      byte dyn[];
      byte assoc[int];
      v = -5;
      q = {9'd251};
      `checkd(v inside {q}, 1'b1);
      w = 9'd300;
      fixed = '{44, 1};
      `checkd(w inside {fixed}, 1'b0);
      w = 9'd44;
      `checkd(w inside {fixed}, 1'b1);
      dyn = '{-2, 3};
      h = -2;
      `checkd(h inside {dyn}, 1'b1);
      h = 254;
      `checkd(h inside {dyn}, 1'b0);
      assoc[5] = -2;
      w = 9'h1fe;
      `checkd(w inside {assoc}, 1'b0);
      w = 9'd254;
      `checkd(w inside {assoc}, 1'b1);
    end
    begin
      // An impure expression is evaluated once
      `checkd(next_value(-5) inside {[9'd0 : 9'd300], 9'd400}, 1'b1);
      `checkd(calls, 1);
      `checkd(next_value(-5) inside {9'd400, 9'd251}, 1'b1);
      `checkd(calls, 2);
      `checkd(next_value(-5) inside {[-8'sd10 : -8'sd1]}, 1'b1);
      `checkd(calls, 3);
    end
    begin
      // An impure expression matches as a variable holding its value
      bit signed [2:0] v;
      v = -3'sd1;
      `checkd(v inside {5'sd2, 5'd4, 5'sd31}, 1'b1);
      `checkd(next_small(v) inside {5'sd2, 5'd4, 5'sd31}, 1'b1);
      `checkd(calls, 4);
      `checkd(v inside {[5'sd30 : 5'sd31], 5'd4}, 1'b1);
      `checkd(next_small(v) inside {[5'sd30 : 5'sd31], 5'd4}, 1'b1);
      `checkd(calls, 5);
      `checkd(next_small(v) inside {5'd7, 5'd31}, v inside {5'd7, 5'd31});
      `checkd(calls, 6);
    end
    begin
      // An impure expression is evaluated once whatever item can never match; an unsigned
      // 4-bit value is never inside [-5'sd4 : 5'sd3], which compares unsigned
      bit [3:0] n;
      int r;
      n = 9;
      calls = 0;
      `checkd(next_nibble(n) inside {[-5'sd4 : 5'sd3], 9'd9}, 1'b1);
      `checkd(calls, 1);
      `checkd(next_nibble(n) inside {[-5'sd4 : 5'sd3]}, 1'b0);
      `checkd(calls, 2);
      `checkd(next_nibble(n) inside {9'd8, [-5'sd4 : 5'sd3], 9'd9}, 1'b1);
      `checkd(calls, 3);
      `checkd(next_nibble(n) inside {9'd9, [-5'sd4 : 5'sd3]}, 1'b1);
      `checkd(calls, 4);
      `checkd(next_nibble(n) inside {[4'd0 : 4'd15], [-5'sd4 : 5'sd3]}, 1'b1);
      `checkd(calls, 5);
      case (next_nibble(n)) inside
        [-5'sd4 : 5'sd3]: r = 1;
        9'd9: r = 2;
        default: r = 0;
      endcase
      `checkd(r, 2);
      `checkd(calls, 6);
    end
    begin
      // An operator on an impure expression takes the width of each comparison, so 15 + 1
      // keeps its carry against a 5-bit item, as it does for a variable
      bit [3:0] n;
      int r;
      n = 15;
      calls = 0;
      `checkd((n + 4'd1) inside {5'd16}, 1'b1);
      `checkd((next_nibble(n) + 4'd1) inside {5'd16}, 1'b1);
      `checkd(calls, 1);
      `checkd((next_nibble(n) + 4'd1) inside {[5'd16 : 5'd20]}, 1'b1);
      `checkd(calls, 2);
      `checkd((next_nibble(n) + 4'd1) inside {4'd0}, 1'b1);
      `checkd(calls, 3);
      `checkd((next_nibble(n) + next_nibble(4'd9)) inside {5'd24, 4'd8}, 1'b1);
      `checkd(calls, 5);
      `checkd((next_nibble(n) + 4'd1) inside {[-5'sd4 : 5'sd3], 5'd16}, 1'b1);
      `checkd(calls, 6);
      case (next_nibble(n) + 4'd1) inside
        5'd16: r = 1;
        default: r = 0;
      endcase
      `checkd(r, 1);
      `checkd(calls, 7);
      `checkd((-n) inside {5'd17}, 1'b1);
      `checkd((-next_nibble(n)) inside {5'd17}, 1'b1);
      `checkd(calls, 8);
      // Only the selected or needed operand is evaluated
      `checkd((n[0] ? next_nibble(n) : next_nibble(4'd2)) inside {4'd15, 5'd2}, 1'b1);
      `checkd(calls, 9);
      `checkd((n == 0 && next_nibble(n) == 0) inside {1'b0}, 1'b1);
      `checkd(calls, 9);
      // A real expression is evaluated once too
      `checkd(next_real(1.5) inside {[1.0 : 2.0], 3.0}, 1'b1);
      `checkd(calls, 10);
    end
    begin
      // A conditional operand evaluates an impure term of an arm only when the arm is
      // selected, and the arm takes the width of each comparison
      bit [3:0] n;
      bit pick;
      int r;
      n = 15;
      pick = 1;
      calls = 0;
      `checkd((pick ? n + 4'd1 : 4'd0) inside {5'd16}, 1'b1);
      `checkd((pick ? next_nibble(n) + 4'd1 : 4'd0) inside {5'd16}, 1'b1);
      `checkd((pick ? next_nibble(n) + 4'd1 : other_nibble()) inside {5'd16}, 1'b1);
      `checkd(calls, 2);
      `checkd(other_calls, 0);
      pick = 0;
      `checkd((pick ? next_nibble(n) + 4'd1 : other_nibble()) inside {5'd16}, 1'b0);
      `checkd((pick ? next_nibble(n) + 4'd1 : other_nibble() + 4'd1) inside {5'd1}, 1'b1);
      `checkd(calls, 2);
      `checkd(other_calls, 2);
      pick = 1;
      `checkd((pick ? (n[0] ? next_nibble(n) + 4'd1 : other_nibble()) : 4'd0)
              inside {[5'd16 : 5'd20]}, 1'b1);
      `checkd(calls, 3);
      `checkd((pick ? next_nibble(n) + 4'd1 : other_nibble()) inside {[-5'sd4 : 5'sd3], 5'd16},
              1'b1);
      `checkd(calls, 4);
      case (pick ? next_nibble(n) + 4'd1 : other_nibble()) inside
        5'd16: r = 1;
        default: r = 0;
      endcase
      `checkd(r, 1);
      `checkd(calls, 5);
      `checkd(other_calls, 2);
      // An impure condition is evaluated once
      `checkd((next_nibble(n) == 15 ? n + 4'd1 : 4'd0) inside {5'd16}, 1'b1);
      `checkd(calls, 6);
      // A logical operator has self-determined operands, and evaluates its right side only
      // when needed
      `checkd((n == 15 && next_nibble(n) + 4'd1 == 5'd16) inside {1'b1}, 1'b1);
      `checkd(calls, 7);
      `checkd((n == 15 || next_nibble(n) == 0) inside {1'b1}, 1'b1);
      `checkd((n != 15 -> next_nibble(n) == 0) inside {1'b1}, 1'b1);
      `checkd(calls, 7);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
