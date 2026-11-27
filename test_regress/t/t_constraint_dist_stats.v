// DESCRIPTION: Verilator: Independent DIST behavior and distribution checks
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); `stop; end while (0);
// verilog_format: on

class DistOperands;
  rand bit [7:0] a, b, z;
  bit [7:0] a_input;
  bit [7:0] zero_item = 8'd129;
  constraint c {
    a == a_input;
    b == 8'd128;
    z == 8'd129;
    // The first item compares an 8-bit sum (0); the second compares a 16-bit sum (256).
    // verilator lint_off WIDTHEXPAND
    (a + b) dist {8'd0 := 1, 16'd300 := 1, zero_item := 0};
    // verilator lint_on WIDTHEXPAND
  }
endclass

// An eligible site whose weights are all zero has no legal value.
class IndependentZero;
  rand bit [7:0] x, offset;
  constraint c {
    offset == 8'd0;
    (x + offset) dist {8'd1 := 0, 8'd2 := 0};
  }
endclass

class StagedDist;
  rand bit [2:0] x, y;
  int weight;
  constraint c {
    solve x before y;
    x dist {3'd3 := weight, 3'd6 := 1};
    y != x;
  }
endclass

class ClippedMassBase;
  rand bit [7:0] x, offset;
  bit enabled;
  constraint c {
    offset == 8'd0;
    x >= 8'd102;
    if (enabled) {
      (x + offset) dist {[8'd100:8'd102] := 1, 8'd103 :/ 1, 8'd99 := 65535};
    } else x == 8'd104;
  }
endclass

class ClippedMass extends ClippedMassBase;
  rand bit [7:0] tag;
  rand bit [7:0] spare;
  bit force_free_x;
  constraint c_tag {tag == 8'd42;}
  constraint c_free_x {if (force_free_x) x == 8'd77;}
endclass

package DistWeights;
  function automatic int increment(int weight);
    return weight + 1;
  endfunction
endpackage

class StateWeightDist;
  rand bit [7:0] x, offset;
  int state_weight;
  constraint c {
    offset == 8'd0;
    x >= 8'd102;
    (x + offset) dist {[8'd100:8'd102] := DistWeights::increment(state_weight),
                       8'd103 :/ 1, 8'd99 := 65535};
  }
endclass

class SignedDistBase;
  rand bit signed [7:0] x, offset;
  constraint c_offset {offset == 8'sd0;}
  constraint c_dist {(x + offset) dist {[-8'sd8:-8'sd6] :/ 15, 8'sd5 := 1};}
endclass

class SignedDistDerived extends SignedDistBase;
  rand bit signed [7:0] y;
  constraint c_derived {
    x != -8'sd8;
    y == x + 8'sd1;
  }
endclass

class CollectionDist;
  rand bit [7:0] q[$];
  rand bit [7:0] a[int];
  rand bit [7:0] offset;
  function new();
    // Preallocated, as a random size is solved in a phase of its own
    q = '{8'd0, 8'd0};
    a[-3] = '0;
    a[7] = '0;
  endfunction
  constraint c {
    offset == 8'd0;
    foreach (q[i]) (q[i] + offset) dist {8'd9 := (i == 0 ? 15 : 1),
                                        8'd11 := (i == 0 ? 1 : 15)};
    foreach (a[i]) (a[i] + offset) dist {8'd9 := (i < 0 ? 15 : 1),
                                        8'd11 := (i < 0 ? 1 : 15)};
  }
endclass

class MixedSignOpen;
  rand bit signed [7:0] x, offset;
  bit upper;
  constraint c {
    x == 8'sd0;
    offset == 8'sd0;
    // verilator lint_off WIDTHEXPAND
    if (upper) (x + offset) dist {[16'd0:$] :/ 1};
    else (x + offset) dist {[$:16'd200] :/ 1};
    // verilator lint_on WIDTHEXPAND
  }
endclass

class SiblingBase;
  rand bit tag;
endclass

class SiblingStaged extends SiblingBase;
  rand bit after_tag;
  constraint c_phase {solve tag before after_tag; after_tag != tag;}
endclass

class SiblingIndependent extends SiblingBase;
  rand bit [7:0] x, offset;
  constraint c {
    offset == 8'd0;
    x >= 8'd102;
    (x + offset) dist {[8'd100:8'd102] := 1, 8'd103 :/ 1, 8'd99 := 65535};
  }
endclass

class SignedEligible;
  rand bit signed [7:0] s, offset;
  constraint c {
    offset == 8'sd0;
    s >= -8'sd2;
    (s + offset) dist {[-8'sd4:-8'sd2] := 1, 8'sd3 :/ 1, -8'sd5 := 65535};
  }
endclass

class DisabledStateDist;
  rand bit [7:0] x, offset;
  bit en, implication;
  constraint c {
    offset == 8'd0;
    x inside {8'd1, 8'd2};
    if (implication) en -> (x + offset) dist {8'd1 := 1};
    else if (en) (x + offset) dist {8'd1 := 1};
  }
endclass

class OpenRangeFallback;
  rand bit [7:0] x, offset;
  bit [7:0] requested;
  constraint c {
    x == requested;
    offset == 8'd0;
    (x + offset) dist {[250:$] := 1, [0:9] := 1};
  }
endclass

class WideOpenFallback;
  rand bit [79:0] x, offset;
  bit [79:0] requested;
  constraint c {
    x == requested;
    offset == 80'd0;
    (x + offset) dist {[$:80'd200] :/ 1};
  }
endclass

class ClosedFallback;
  rand bit signed [7:0] x, offset;
  constraint c {
    x == 8'sd0;
    offset == 8'sd0;
    (x + offset) dist {[-8'sd2:8'd3] :/ 1};
  }
endclass

class WideBoundAdd;
  rand bit [7:0] a, b;
  bit [7:0] b_input;
  constraint c {
    a == 8'd255;
    b == b_input;
    // The sum must be evaluated in the wider range context, not wrapped to eight bits.
    // verilator lint_off WIDTHEXPAND
    (a + b) dist {[8'd1:16'd300] :/ 1};
    // verilator lint_on WIDTHEXPAND
  }
endclass

class AssocSelect;
  rand int unsigned k;
  rand bit [7:0] offset;
  bit [7:0] indexed[int unsigned];
  function new();
    indexed[0] = 8'd102;
    indexed[1] = 8'd103;
  endfunction
  constraint c {
    k inside {[0:1]};
    offset == 8'd0;
    (indexed[k] + offset) dist {8'd102 := 1, 8'd103 := 19};
  }
endclass

class DistChild;
  rand bit [7:0] y;
endclass

class GlobalDistOwner;
  rand DistChild child;
  rand bit [7:0] x, offset;
  function new();
    child = new;
  endfunction
  constraint c {
    child.y == 8'd42;
    offset == 8'd0;
    x >= 8'd102;
    (x + offset) dist {[8'd100:8'd102] := 1, 8'd103 :/ 1, 8'd99 := 65535};
  }
endclass

class InlineDistOperands;
  rand bit [7:0] x, offset;
endclass

class InlinePhasedDist;
  rand bit [2:0] x, y;
  int weight;
endclass

class DerivedFromPhase extends SiblingStaged;
  rand bit [7:0] x, offset;
  constraint c_local {
    offset == 8'd0;
    x >= 8'd102;
    (x + offset) dist {[8'd100:8'd102] := 1, 8'd103 :/ 1, 8'd99 := 65535};
  }
endclass

class DistLegacyWide;
  rand bit signed [79:0] x;
  rand bit after_x;
  constraint c {
    solve x before after_x;
    x dist {[80'sd3:80'sd10] := 1};
  }
endclass

class DistWideMulti;
  rand bit [79:0] x, offset;
  constraint c {
    offset == 80'd0;
    (x + offset) dist {[80'd3:80'd6] := 1, [80'd7:80'd8] := 6};
  }
endclass

class StaticWideRange;
  rand bit [1023:0] x;
  constraint c {
    x dist {
      [1024'd0:1024'd1] := 32'd1,
      [1024'd4:1024'd5] := 32'd1,
      [1024'd8:1024'd9] := 32'd1,
      [1024'd12:1024'd13] := 32'd1,
      [1024'd16:1024'd17] := 32'd1,
      [1024'd20:1024'd21] := 32'd1,
      [1024'd24:1024'd25] := 32'd1,
      [1024'd28:1024'd29] := 32'd1,
      [1024'd32:1024'd33] := 32'd1,
      [1024'd36:1024'd37] := 32'd1,
      [1024'd40:1024'd41] := 32'd1,
      [1024'd44:1024'd45] := 32'd1,
      [1024'd48:1024'd49] := 32'd1,
      [1024'd52:1024'd53] := 32'd1000000,
      [1024'd56:1024'd57] := 32'd1,
      [1024'd60:1024'd61] := 32'd1,
      [1024'd64:1024'd65] := 32'd1,
      [1024'd68:1024'd69] := 32'd1,
      [1024'd72:1024'd73] := 32'd1,
      [1024'd76:1024'd77] := 32'd1,
      [1024'd80:1024'd81] := 32'd1,
      [1024'd84:1024'd85] := 32'd1,
      [1024'd88:1024'd89] := 32'd1,
      [1024'd92:1024'd93] := 32'd1,
      [1024'd96:1024'd97] := 32'd1,
      [1024'd100:1024'd101] := 32'd1,
      [1024'd104:1024'd105] := 32'd1
    };
  }
endclass

class WideSingletons;
  rand bit [1022:0] x;
  constraint c {
    x dist {
      1023'd0 := 1024'd1,
      1023'd1 := 1024'd1,
      1023'd2 := 1024'd1,
      1023'd3 := 1024'd1,
      1023'd4 := 1024'd1,
      1023'd5 := 1024'd1,
      1023'd6 := 1024'd1,
      1023'd7 := 1024'd1,
      1023'd8 := 1024'd1,
      1023'd9 := 1024'd1,
      1023'd10 := 1024'd1,
      1023'd11 := 1024'd1,
      1023'd12 := 1024'd1,
      1023'd13 := 1024'd1,
      1023'd14 := 1024'd1,
      1023'd15 := 1024'd1,
      1023'd16 := 1024'd1,
      1023'd17 := 1024'd1,
      1023'd18 := 1024'd1,
      1023'd19 := 1024'd1,
      1023'd20 := 1024'd1,
      1023'd21 := 1024'd1,
      1023'd22 := 1024'd1,
      1023'd23 := 1024'd1,
      1023'd24 := 1024'd1,
      1023'd25 := 1024'd1,
      1023'd26 := 1024'd1,
      1023'd27 := 1024'd1,
      1023'd28 := 1024'd1,
      1023'd29 := 1024'd1000000,
      1023'd30 := 1024'd1,
      1023'd31 := 1024'd1,
      1023'd32 := 1024'd1,
      1023'd33 := 1024'd1,
      1023'd34 := 1024'd1,
      1023'd35 := 1024'd1,
      1023'd36 := 1024'd1,
      1023'd37 := 1024'd1,
      1023'd38 := 1024'd1,
      1023'd39 := 1024'd1,
      1023'd40 := 1024'd1,
      1023'd41 := 1024'd1,
      1023'd42 := 1024'd1,
      1023'd43 := 1024'd1,
      1023'd44 := 1024'd1,
      1023'd45 := 1024'd1,
      1023'd46 := 1024'd1,
      1023'd47 := 1024'd1,
      1023'd48 := 1024'd1,
      1023'd49 := 1024'd1,
      1023'd50 := 1024'd1,
      1023'd51 := 1024'd1,
      1023'd52 := 1024'd1,
      1023'd53 := 1024'd1,
      1023'd54 := 1024'd1,
      1023'd55 := 1024'd1,
      1023'd56 := 1024'd1
    };
  }
endclass

class LongScalarName;
  rand bit [1022:0] wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_ident;
  constraint c {
    wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_ident dist {
      1023'd0 := 1023'd1,
      1023'd1 := 1023'd1,
      1023'd2 := 1023'd1,
      1023'd3 := 1023'd1,
      1023'd4 := 1023'd1,
      1023'd5 := 1023'd1,
      1023'd6 := 1023'd1,
      1023'd7 := 1024'd1,
      1023'd8 := 1024'd1,
      1023'd9 := 1024'd1,
      1023'd10 := 1024'd1,
      1023'd11 := 1024'd1,
      1023'd12 := 1024'd1,
      1023'd13 := 1024'd1,
      1023'd14 := 1024'd1,
      1023'd15 := 1024'd1,
      1023'd16 := 1024'd1,
      1023'd17 := 1024'd1,
      1023'd18 := 1024'd1,
      1023'd19 := 1024'd1,
      1023'd20 := 1024'd1,
      1023'd21 := 1024'd1,
      1023'd22 := 1024'd1,
      1023'd23 := 1024'd1,
      1023'd24 := 1024'd1,
      1023'd25 := 1024'd1,
      1023'd26 := 1024'd1,
      1023'd27 := 1024'd1,
      1023'd28 := 1024'd1,
      1023'd29 := 1024'd1000000,
      1023'd30 := 1024'd1,
      1023'd31 := 1024'd1,
      1023'd32 := 1024'd1,
      1023'd33 := 1024'd1,
      1023'd34 := 1024'd1,
      1023'd35 := 1024'd1,
      1023'd36 := 1024'd1,
      1023'd37 := 1024'd1,
      1023'd38 := 1024'd1,
      1023'd39 := 1024'd1,
      1023'd40 := 1024'd1,
      1023'd41 := 1024'd1,
      1023'd42 := 1024'd1,
      1023'd43 := 1024'd1,
      1023'd44 := 1024'd1,
      1023'd45 := 1024'd1,
      1023'd46 := 1024'd1,
      1023'd47 := 1024'd1,
      1023'd48 := 1024'd1,
      1023'd49 := 1024'd1,
      1023'd50 := 1024'd1,
      1023'd51 := 1024'd1,
      1023'd52 := 1024'd1,
      1023'd53 := 1024'd1,
      1023'd54 := 1024'd1
    };
  }
endclass

class GuardedSingletons;
  rand bit [1023:0] x;
  rand bit [4096:0] payload[2];
  constraint c {
    foreach (payload[i]) payload[i] != '1;
    x != 1024'd0;
    x dist {
      1024'd0 := 524'd1,
      1024'd1 := 524'd1,
      1024'd2 := 524'd1,
      1024'd3 := 524'd1,
      1024'd4 := 524'd1,
      1024'd5 := 524'd1,
      1024'd6 := 524'd1,
      1024'd7 := 524'd1,
      1024'd8 := 524'd1,
      1024'd9 := 524'd1,
      1024'd10 := 524'd1,
      1024'd11 := 524'd1,
      1024'd12 := 524'd1,
      1024'd13 := 524'd1,
      1024'd14 := 524'd1,
      1024'd15 := 524'd1,
      1024'd16 := 524'd1,
      1024'd17 := 524'd1,
      1024'd18 := 524'd1,
      1024'd19 := 524'd1,
      1024'd20 := 524'd1,
      1024'd21 := 524'd1,
      1024'd22 := 524'd1,
      1024'd23 := 524'd1,
      1024'd24 := 524'd1,
      1024'd25 := 524'd1,
      1024'd26 := 524'd1,
      1024'd27 := 524'd1,
      1024'd28 := 524'd1,
      1024'd29 := 524'd1000000,
      1024'd30 := 524'd1,
      1024'd31 := 524'd1,
      1024'd32 := 524'd1,
      1024'd33 := 524'd1,
      1024'd34 := 524'd1,
      1024'd35 := 524'd1,
      1024'd36 := 524'd1,
      1024'd37 := 524'd1,
      1024'd38 := 524'd1,
      1024'd39 := 524'd1,
      1024'd40 := 524'd1,
      1024'd41 := 524'd1,
      1024'd42 := 524'd1,
      1024'd43 := 524'd1,
      1024'd44 := 524'd1,
      1024'd45 := 524'd1,
      1024'd46 := 524'd1,
      1024'd47 := 524'd1,
      1024'd48 := 524'd1,
      1024'd49 := 524'd1,
      1024'd50 := 524'd1,
      1024'd51 := 524'd1,
      1024'd52 := 524'd1,
      1024'd53 := 524'd1,
      1024'd54 := 524'd1,
      1024'd55 := 524'd1,
      1024'd56 := 524'd1,
      1024'd57 := 524'd1,
      1024'd58 := 524'd1,
      1024'd59 := 524'd1,
      1024'd60 := 524'd1,
      1024'd61 := 524'd1,
      1024'd62 := 524'd1,
      1024'd63 := 524'd1,
      1024'd64 := 524'd1,
      1024'd65 := 524'd1,
      1024'd66 := 524'd1,
      1024'd67 := 524'd1,
      1024'd68 := 524'd1,
      1024'd69 := 524'd1,
      1024'd70 := 524'd1,
      1024'd71 := 524'd1,
      1024'd72 := 524'd1,
      1024'd73 := 524'd1,
      1024'd74 := 524'd1,
      1024'd75 := 524'd1,
      1024'd76 := 524'd1,
      1024'd77 := 524'd1,
      1024'd78 := 524'd1,
      1024'd79 := 524'd1,
      1024'd80 := 524'd1,
      1024'd81 := 524'd1,
      1024'd82 := 524'd1,
      1024'd83 := 524'd1,
      1024'd84 := 524'd1,
      1024'd85 := 524'd1,
      1024'd86 := 524'd1,
      1024'd87 := 524'd1,
      1024'd88 := 524'd1,
      1024'd89 := 524'd1,
      1024'd90 := 524'd1,
      1024'd91 := 524'd1,
      1024'd92 := 524'd1,
      1024'd93 := 524'd1,
      1024'd94 := 524'd1
    };
  }
endclass

class LongPackedSlice;
  rand bit [1023:0] wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_ident;
  constraint c {
    wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_ident[1022:0] dist {
      1023'd0 := 1023'd1,
      1023'd1 := 1023'd1,
      1023'd2 := 1023'd1,
      1023'd3 := 1023'd1,
      1023'd4 := 1023'd1,
      1023'd5 := 1023'd1,
      1023'd6 := 1023'd1,
      1023'd7 := 1024'd1,
      1023'd8 := 1024'd1,
      1023'd9 := 1024'd1,
      1023'd10 := 1024'd1,
      1023'd11 := 1024'd1,
      1023'd12 := 1024'd1,
      1023'd13 := 1024'd1,
      1023'd14 := 1024'd1,
      1023'd15 := 1024'd1,
      1023'd16 := 1024'd1,
      1023'd17 := 1024'd1,
      1023'd18 := 1024'd1,
      1023'd19 := 1024'd1,
      1023'd20 := 1024'd1,
      1023'd21 := 1024'd1,
      1023'd22 := 1024'd1,
      1023'd23 := 1024'd1,
      1023'd24 := 1024'd1,
      1023'd25 := 1024'd1,
      1023'd26 := 1024'd1,
      1023'd27 := 1024'd1,
      1023'd28 := 1024'd1,
      1023'd29 := 1024'd1000000,
      1023'd30 := 1024'd1,
      1023'd31 := 1024'd1,
      1023'd32 := 1024'd1,
      1023'd33 := 1024'd1,
      1023'd34 := 1024'd1,
      1023'd35 := 1024'd1,
      1023'd36 := 1024'd1,
      1023'd37 := 1024'd1,
      1023'd38 := 1024'd1,
      1023'd39 := 1024'd1,
      1023'd40 := 1024'd1,
      1023'd41 := 1024'd1,
      1023'd42 := 1024'd1,
      1023'd43 := 1024'd1,
      1023'd44 := 1024'd1,
      1023'd45 := 1024'd1,
      1023'd46 := 1024'd1,
      1023'd47 := 1024'd1,
      1023'd48 := 1024'd1,
      1023'd49 := 1024'd1,
      1023'd50 := 1024'd1,
      1023'd51 := 1024'd1,
      1023'd52 := 1024'd1,
      1023'd53 := 1024'd1,
      1023'd54 := 1024'd1
    };
  }
endclass

class FirstPredicateWide;
  rand bit [1022:0] x;
  constraint c {
    x dist {
      1023'd0 := 992'd1,
      1023'd1 := 992'd1,
      1023'd2 := 992'd1,
      1023'd3 := 992'd1,
      1023'd4 := 992'd1,
      1023'd5 := 992'd1,
      1023'd6 := 992'd1,
      1023'd7 := 992'd1,
      1023'd8 := 992'd1,
      1023'd9 := 992'd1,
      1023'd10 := 992'd1,
      1023'd11 := 992'd1,
      1023'd12 := 992'd1,
      1023'd13 := 992'd1,
      1023'd14 := 992'd1,
      1023'd15 := 992'd1,
      1023'd16 := 992'd1,
      1023'd17 := 992'd1,
      1023'd18 := 992'd1,
      1023'd19 := 992'd1,
      1023'd20 := 992'd1,
      1023'd21 := 992'd1,
      1023'd22 := 992'd1,
      1023'd23 := 992'd1,
      1023'd24 := 992'd1,
      1023'd25 := 1024'd1,
      1023'd26 := 1024'd1,
      1023'd27 := 1024'd1,
      1023'd28 := 1024'd1,
      1023'd29 := 1024'd1,
      1023'd30 := 1024'd1,
      1023'd31 := 1024'd1,
      1023'd32 := 1024'd1,
      1023'd33 := 1024'd1,
      1023'd34 := 1024'd1,
      1023'd35 := 1024'd1,
      1023'd36 := 1024'd1,
      1023'd37 := 1024'd1,
      1023'd38 := 1024'd1,
      1023'd39 := 1024'd1,
      1023'd40 := 1024'd1,
      1023'd41 := 1024'd1,
      1023'd42 := 1024'd1,
      1023'd43 := 1024'd1,
      1023'd44 := 1024'd1,
      1023'd45 := 1024'd1,
      1023'd46 := 1024'd1000000
    };
  }
endclass

class WidePopcount;
  rand bit [1023:0] x;
  constraint c {
    x[1023:7] == '0;
    $countones(x) dist {
      0 := 32'd1,
      1 := 32'd1,
      2 := 32'd1,
      3 := 32'd1,
      4 := 32'd1,
      5 := 32'd1000000,
      6 := 32'd1,
      7 := 32'd1,
      8 := 32'd1,
      9 := 32'd1,
      10 := 32'd1,
      11 := 32'd1,
      12 := 32'd1,
      13 := 32'd1,
      14 := 32'd1,
      15 := 32'd1,
      16 := 32'd1,
      17 := 32'd1,
      18 := 32'd1,
      19 := 32'd1,
      20 := 32'd1,
      21 := 32'd1,
      22 := 32'd1,
      23 := 32'd1,
      24 := 32'd1,
      25 := 32'd1,
      26 := 32'd1,
      27 := 32'd1,
      28 := 32'd1,
      29 := 32'd1,
      30 := 32'd1,
      31 := 32'd1,
      32 := 32'd1,
      33 := 32'd1,
      34 := 32'd1,
      35 := 32'd1,
      36 := 32'd1,
      37 := 32'd1,
      38 := 32'd1,
      39 := 32'd1,
      40 := 32'd1,
      41 := 32'd1,
      42 := 32'd1,
      43 := 32'd1,
      44 := 32'd1,
      45 := 32'd1,
      46 := 32'd1,
      47 := 32'd1
    };
  }
endclass

class HardForeach;
  rand bit [127:0] values;
  rand bit offset;
  constraint c {
    offset == 0;
    foreach (values[i]) (values[i] ^ offset) dist {1'b1 := 32'd9, 1'b0 := 32'd1};
  }
endclass

class WeightSource;
  int weight = 3;
  int member_weight = 2;
  function int get();
    return weight;
  endfunction
endclass

// Operands that keep procedural bucket selection.
class ProceduralOperands;
  rand bit [7:0] x, y, z, w, offset;
  rand bit enable;
  rand bit [7:0] values[4];
  WeightSource source = new;
  int index = 1;
  constraint c {
    offset == 0;
    // Weight read through an object handle
    (x + offset) dist {8'd1 := source.get(), 8'd2 := 1};
    // Weight read from a member through an object handle
    (w + offset) dist {8'd7 := source.member_weight, 8'd8 := 1};
    // Random implication guard
    enable -> (y + offset) dist {8'd3 := 1, 8'd4 := 1};
    // Element of an array with controlled rand_mode
    (values[index] + offset) dist {8'd5 := 1, 8'd6 := 1};
    // verilator lint_off WIDTHEXPAND
    // A range in a narrower comparison domain than another item
    (z + offset) dist {[16'd1:16'd300] := 1, 300000 := 1};
    // verilator lint_on WIDTHEXPAND
  }
endclass

// Counted state weights format as solver arithmetic, not as single literals.
class ExpandedWeight;
  rand bit [2:0] x, offset;
  bit [1023:0] ones = '1;
  constraint c {
    offset == 0;
    (x + offset) dist {
      3'd1 := $countones(ones),
      3'd2 := $countones(ones),
      3'd3 := $countones(ones),
      3'd4 := $countones(ones)
    };
  }
endclass

class TwoSiteDist;
  rand int x, y, bias;
  constraint c {
    bias == 0;
    x > 101;
    (x + bias) dist {[100:102] := 1, 103 := 1};
    (y + bias) dist {8 := 1, 9 := 1};
  }
endclass

// The array variants give P(0) = 1/2 on "edge" elements (i < first || i >= n - last)
// and P(0) = 1/4 on "inner" elements, so the same checker applies to all of them.

// verilog_format: off
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

`define IS_EDGE(i, obj) ((i) < (obj).first || (i) >= (obj).n - (obj).last)

class Stats;
  string name;
  int edge_zero, edge_total, inner_zero, inner_total;
  function new(string name);
    this.name = name;
  endfunction
  function void add(bit is_edge, bit is_zero);
    if (is_edge) begin
      edge_total++;
      if (is_zero) edge_zero++;
    end
    else begin
      inner_total++;
      if (is_zero) inner_zero++;
    end
  endfunction
  function void check();
    int edge_pct, inner_pct;
    if (edge_total < 100 || inner_total < 100) begin
      $write("%%Error: %s: too few samples (edge=%0d inner=%0d)\n", name, edge_total, inner_total);
      `stop;
    end
    edge_pct = edge_zero * 100 / edge_total;
    inner_pct = inner_zero * 100 / inner_total;
`ifdef TEST_VERBOSE
    $display("%s: edge P(0)=%0d%% (%0d)  inner P(0)=%0d%% (%0d)", name, edge_pct, edge_total,
             inner_pct, inner_total);
`endif
    `check_range(edge_pct, 38, 62);
    `check_range(inner_pct, 13, 37);
  endfunction
endclass

// Same weights, but the variables they depend on are not random
class ClsFixed;
  int unsigned n = 6, first = 2, last = 2;
  rand bit [1:0] a[];
  rand bit [1:0] b[];
  constraint c {
    a.size() == n;
    b.size() == n;
    foreach (a[i]) {
      a[i] dist {
        0 :/ ((i < first || i >= n - last) ? 50 : 25),
        [1:3] :/ ((i < first || i >= n - last) ? 50 : 75)
      };
      b[i] dist {
        0 :/ ((i < first || i >= n - last) ? 50 : 25),
        [1:3] :/ ((i < first || i >= n - last) ? 50 : 75)
      };
    }
  }
endclass

class ClsInner;
  rand bit [1:0] w;
  constraint c_inner {w != 0;}
endclass

class ClsNotPinned;
  rand ClsInner inner;
  rand bit y;
  constraint c {y dist {0 := inner.w, 1 := 1};}
  function new();
    inner = new;
  endfunction
endclass

// Counts, per element, solves where two arrays drew different buckets.
// A draw shared between arrays would give 0.
`define COUNT_DIFF(diff, x, y) \
  foreach (x[i]) if ((x[i] == 0) != (y[i] == 0)) diff++;

module t;
  class SoftDist;
    rand bit [7:0] x, offset;
    int unsigned weight = 40;
    constraint c {
      offset == 0;
      soft (x + offset) dist {8'd3 := weight, 8'd9 := 1};
    }
  endclass

  class CompletedDraw;
    rand bit [4096:0] payload[80];
    rand bit [3:0] pick, offset;
    constraint c {
      payload[3] != '1;
      offset == 0;
      (pick + offset) dist {4'd3 := 1, 4'd7 := 5};
    }
  endclass

  class PointTrials;
    rand bit [7:0] pick, offset;
    constraint c {
      offset == 0;
      pick inside {8'd127, 8'd128};
      (pick + offset) dist {[8'd0:8'd127] :/ 60000, 8'd128 :/ 1};
    }
  endclass

  task automatic run_item_width();
    begin
      automatic StagedDist obj = new;
      int balanced_count, heavy_count, ok;
      balanced_count = 0;
      heavy_count = 0;
      obj.srandom(32'h31415926);
      for (int i = 0; i < 256; ++i) begin
        obj.weight = i[0] ? 99 : 1;
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {3'd3, 3'd6}), 1'b1);
        `checkd((obj.y != obj.x), 1'b1);
        if (i[0]) heavy_count += int'(obj.x == 3'd3);
        else balanced_count += int'(obj.x == 3'd3);
      end
      // The same staged distribution gives nearly 50% or 99% for x == 3.
      `checkd((balanced_count inside {[42:86]}), 1'b1);
      `checkd((heavy_count >= 115), 1'b1);
    end
    begin
      automatic IndependentZero obj = new;
      int ok;
      obj.x = 8'd99;
      ok = obj.randomize();
      `checkd(ok, 0);
      `checkd(obj.x, 8'd99);
    end
    begin
      automatic DistOperands obj = new;
      int ok;
      obj.a_input = 8'd128;
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.a, 8'd128);
      `checkd(obj.b, 8'd128);
      `checkd(obj.z, 8'd129);
      // The 8-bit sum now equals zero_item; only a zero-weight item matches.
      obj.a_input = 8'd1;
      ok = obj.randomize();
      `checkd(ok, 0);
      `checkd(obj.a, 8'd128);

      obj.a_input = 8'd128;
      obj.b.rand_mode(0);
      obj.z.rand_mode(0);
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.a, 8'd128);
      obj.a.rand_mode(0);
      ok = obj.randomize();
      `checkd(ok, 1);
      obj.a = 8'd1;
      obj.a_input = 8'd1;
      ok = obj.randomize();
      `checkd(ok, 0);
      `checkd(obj.a, 8'd1);

      obj.a.rand_mode(1);
      obj.a_input = 8'd128;
      ok = obj.randomize(a);
      `checkd(ok, 1);
      `checkd(obj.a, 8'd128);
      `checkd(obj.b, 8'd128);
      `checkd(obj.z, 8'd129);
      obj.a_input = 8'd1;
      ok = obj.randomize(a);
      `checkd(ok, 0);
      `checkd(obj.a, 8'd128);
    end
    begin
      automatic CollectionDist obj = new;
      int q_first, q_last, a_first, a_last, ok;
      q_first = 0;
      q_last = 0;
      a_first = 0;
      a_last = 0;
      obj.srandom(73);
      repeat (128) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd(obj.q.size(), 2);
        `checkd(obj.a.num(), 2);
        `checkd(obj.a.exists(-3), 1);
        `checkd(obj.a.exists(7), 1);
        foreach (obj.q[i]) `checkd((obj.q[i] inside {8'd9, 8'd11}), 1'b1);
        foreach (obj.a[i]) `checkd((obj.a[i] inside {8'd9, 8'd11}), 1'b1);
        q_first += int'(obj.q[0] == 8'd9);
        q_last += int'(obj.q[1] == 8'd11);
        a_first += int'(obj.a[-3] == 8'd9);
        a_last += int'(obj.a[7] == 8'd11);
      end
      `checkd((q_first >= 102), 1'b1);
      `checkd((q_last >= 102), 1'b1);
      `checkd((a_first >= 102), 1'b1);
      `checkd((a_last >= 102), 1'b1);
    end
    begin
      automatic DisabledStateDist obj = new;
      bit saw_other;
      int ok;
      obj.srandom(71);
      for (int i = 0; i < 2; ++i) begin
        obj.implication = i[0];
        saw_other = 0;
        obj.en = 0;
        repeat (32) begin
          ok = obj.randomize();
          `checkd(ok, 1);
          `checkd((obj.x inside {8'd1, 8'd2}), 1'b1);
          saw_other |= obj.x == 8'd2;
        end
        `checkd(saw_other, 1'b1);
        obj.en = 1;
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd(obj.x, 8'd1);
      end
    end
  endtask

  task automatic run_dist_paths();
    begin
      automatic ClosedFallback obj = new;
      int ok;
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 8'sd0);
      `checkd(obj.offset, 8'sd0);
    end
    begin
      automatic AssocSelect obj = new;
      int ok;
      repeat (32) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.k inside {[0:1]}), 1'b1);
        `checkd((obj.indexed[obj.k] inside {8'd102, 8'd103}), 1'b1);
      end
    end
    begin
      automatic InlinePhasedDist obj = new;
      int balanced, heavy, ok;
      balanced = 0;
      heavy = 0;
      obj.srandom(217);
      for (int i = 0; i < 256; ++i) begin
        obj.weight = i[0] ? 99 : 1;
        ok = obj.randomize() with {
          solve x before y;
          x dist {3'd3 := weight, 3'd6 := 1};
          y != x;
        };
        `checkd(ok, 1);
        `checkd((obj.x inside {3'd3, 3'd6}), 1'b1);
        `checkd((obj.y != obj.x), 1'b1);
        if (i[0]) heavy += int'(obj.x == 3'd3);
        else balanced += int'(obj.x == 3'd3);
      end
      `checkd((balanced inside {[42:86]}), 1'b1);
      `checkd((heavy >= 115), 1'b1);
    end
    begin
      automatic ProceduralOperands obj = new;
      int ok;
      obj.values.rand_mode(0);
      obj.values[1] = 8'd5;
      repeat (16) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {8'd1, 8'd2}), 1'b1);
        `checkd((obj.w inside {8'd7, 8'd8}), 1'b1);
        `checkd((!obj.enable || obj.y inside {8'd3, 8'd4}), 1'b1);
        `checkd(obj.values[1], 8'd5);
        `checkd((obj.z inside {[8'd1:8'd255]}), 1'b1);
      end
    end
    begin
      automatic DerivedFromPhase obj = new;
      int ok;
      repeat (32) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.after_tag != obj.tag), 1'b1);
        `checkd((obj.x inside {8'd102, 8'd103}), 1'b1);
      end
    end
  endtask

  task automatic run_wide_stats();
    int randomize_result;
    begin
      automatic ExpandedWeight obj = new;
      bit [7:0] seen;
      int ok;
      seen = 0;
      obj.srandom(93);
      repeat (8) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {[3'd1:3'd4]}), 1'b1);
        seen[obj.x] = 1'b1;
      end
      `checkd(($countones(seen) >= 2), 1'b1);
    end
    // Keep an explicitly staged wide range on the procedural lowering.
    begin
      automatic WidePopcount obj = new;
      int heavy_count, ok;
      heavy_count = 0;
      obj.srandom(775);
      repeat (8) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd(($countones(obj.x) inside {[0:7]}), 1'b1);
        heavy_count += int'($countones(obj.x) == 5);
      end
      `checkd((heavy_count >= 7), 1'b1);
    end

    begin
      automatic DistLegacyWide wide = new();
      randomize_result = wide.randomize();
      `checkd(randomize_result, 1);
      `check_range(wide.x, 3, 10)
    end

    begin
      automatic StaticWideRange obj = new();
      int heavy_count;
      heavy_count = 0;
      obj.srandom(729);
      repeat (96) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `checkd((obj.x <= 1024'd105 && obj.x[1] == 1'b0), 1'b1);
        heavy_count += int'(obj.x inside {[1024'd52:1024'd53]});
      end
      // One bucket dominates the legacy distribution; other ranges remain legal.
      `check_range(heavy_count, 90, 96)
    end

    begin
      automatic WideSingletons obj = new;
      int hits, ok;
      hits = 0;
      obj.srandom(739);
      repeat (96) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x <= 1023'd56), 1'b1);
        hits += int'(obj.x == 1023'd29);
      end
      `checkd((hits >= 90), 1'b1);
    end

    begin
      automatic LongScalarName obj = new;
      int hits, ok;
      hits = 0;
      obj.srandom(739);
      repeat (96) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_ident <= 1023'd54), 1'b1);
        hits += int'(obj.wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_ident == 1023'd29);
      end
      `checkd((hits >= 90), 1'b1);
    end

    begin
      automatic GuardedSingletons obj = new;
      int hits, ok;
      hits = 0;
      obj.srandom(748);
      repeat (96) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        foreach (obj.payload[i]) `checkd((obj.payload[i] != '1), 1'b1);
        `checkd((obj.x inside {[1024'd1:1024'd94]}), 1'b1);
        hits += int'(obj.x == 1024'd29);
      end
      `checkd((hits >= 90), 1'b1);

    end

    begin
      automatic LongPackedSlice obj = new;
      int hits, ok;
      hits = 0;
      obj.srandom(739);
      repeat (96) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_ident[1022:0] <= 1023'd54), 1'b1);
        hits += int'(obj.wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_identifier_kept_in_each_sampling_descriptor_wide_scalar_ident[1022:0] == 1023'd29);
      end
      `checkd((hits >= 90), 1'b1);
    end

    begin
      automatic FirstPredicateWide obj = new;
      int hits, ok;
      hits = 0;
      obj.srandom(763);
      repeat (96) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x <= 1023'd46), 1'b1);
        hits += int'(obj.x == 1023'd46);
      end
      // A site that cannot reserve its first predicate retains legacy weighting.
      `checkd((hits >= 90), 1'b1);
    end

    begin
      automatic DistWideMulti obj = new();
      int upper_count;
      upper_count = 0;
      obj.srandom(87);
      repeat (256) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `check_range(obj.x, 3, 8)
        upper_count += int'(obj.x >= 80'd7);
      end
      // := contributes four units for [3:6] and twelve for [7:8].
      `check_range(upper_count, 158, 226)
    end

  endtask

  task automatic run_weight_arrays();
    localparam int ITERS = 400;
    int randomize_result;

    begin
      static ClsFixed obj = new;
      static Stats s_a = new("fixed.a"), s_b = new("fixed.b");
      static int diff = 0;
      repeat (ITERS) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `checkd(obj.a.size(), obj.n);
        `checkd(obj.b.size(), obj.n);
        foreach (obj.a[i]) begin
          s_a.add(`IS_EDGE(i, obj), obj.a[i] == 0);
          s_b.add(`IS_EDGE(i, obj), obj.b[i] == 0);
        end
        `COUNT_DIFF(diff, obj.a, obj.b);
      end
      s_a.check();
      s_b.check();
      if (diff == 0) begin
        $write("%%Error: fixed: a/b always share bucket\n");
        `stop;
      end
    end

    begin
      static ClsNotPinned obj = new;
      repeat (ITERS) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `check_range(obj.inner.w, 1, 3);
      end
    end

  endtask

  task automatic run_point_cases();
    begin
      automatic TwoSiteDist obj = new;
      int clipped, other, ok;
      clipped = 0;
      other = 0;
      obj.srandom(817);
      repeat (512) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {102, 103}), 1'b1);
        `checkd((obj.y inside {8, 9}), 1'b1);
        clipped += int'(obj.x == 102);
        other += int'(obj.y == 8);
      end
      // The clipped interval retains its declared mass of three, not one.
      `checkd((clipped inside {[353:415]}), 1'b1);
      `checkd((other inside {[215:297]}), 1'b1);
    end
    begin
      automatic ClippedMass obj = new;
      automatic int clipped = 0;
      int ok;
      bit [7:0] first_spare;
      bit saw_new_spare;
      string randstate;
      saw_new_spare = 0;
      obj.srandom(37);
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 8'd104);
      first_spare = obj.spare;
      obj.enabled = 1;
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {8'd102, 8'd103}), 1'b1);
        clipped += int'(obj.x == 8'd102);
        saw_new_spare |= obj.spare != first_spare;
      end
      `checkd(saw_new_spare, 1'b1);
      // The inherited interval has mass 3 despite only one point being feasible.
      `checkd((clipped inside {[158:226]}), 1'b1);
      `checkd(obj.tag, 8'd42);

      // Check-only calls do not sample the active site or change its stored value.
      randstate = obj.get_randstate();
      obj.x = 8'd103;
      repeat (8) begin
        ok = obj.randomize(null);
        `checkd(ok, 1);
        `checkd(obj.x, 8'd103);
      end
      obj.x = 8'd104;
      ok = obj.randomize(null);
      `checkd(ok, 0);
      `checkd(obj.x, 8'd104);
      `checkd((obj.get_randstate() == randstate), 1'b1);

      obj.x = 8'd103;
      obj.offset = 8'd0;
      obj.tag = 8'd0;
      ok = obj.randomize(tag);
      `checkd(ok, 1);
      `checkd(obj.x, 8'd103);
      `checkd(obj.offset, 8'd0);
      `checkd(obj.tag, 8'd42);
      obj.x = 8'd104;
      obj.tag = 8'd0;
      ok = obj.randomize(tag);
      `checkd(ok, 0);
      `checkd(obj.x, 8'd104);
      `checkd(obj.tag, 8'd0);

      obj.x.rand_mode(0);
      obj.offset.rand_mode(0);
      obj.x = 8'd103;
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 8'd103);
      `checkd(obj.tag, 8'd42);
      obj.x = 8'd104;
      ok = obj.randomize();
      `checkd(ok, 0);
      `checkd(obj.x, 8'd104);
      obj.c.constraint_mode(0);
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 8'd104);
      `checkd(obj.tag, 8'd42);
      obj.x.rand_mode(1);
      obj.force_free_x = 1;
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 8'd77);
    end
    begin
      automatic StateWeightDist obj = new;
      int unit_count, heavy_count, ok;
      unit_count = 0;
      heavy_count = 0;
      obj.srandom(51);
      for (int i = 0; i < 256; ++i) begin
        obj.state_weight = i[0] ? 8 : 0;
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {8'd102, 8'd103}), 1'b1);
        if (i[0]) heavy_count += int'(obj.x == 8'd102);
        else unit_count += int'(obj.x == 8'd102);
      end
      // The package function changes the declared mass of the clipped range from 3 to 27.
      `checkd((unit_count inside {[78:112]}), 1'b1);
      `checkd((heavy_count >= 112), 1'b1);
    end
    begin
      automatic SignedDistBase base_obj = new;
      automatic SignedDistDerived obj = new;
      automatic int negative_count = 0;
      int ok;
      ok = base_obj.randomize();
      `checkd(ok, 1);
      `checkd((base_obj.x inside {[-8'sd8:-8'sd6], 8'sd5}), 1'b1);
      obj.srandom(68);
      repeat (128) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {[-8'sd7:-8'sd6], 8'sd5}), 1'b1);
        `checkd(obj.y, (obj.x + 8'sd1));
        negative_count += int'(obj.x < 0);
      end
      `checkd((negative_count >= 102), 1'b1);

      obj.x = 8'sd42;
      // Argument randomization changes x but preserves y, so only x == 5 is feasible.
      obj.y = 8'sd6;
      ok = obj.randomize(x);
      `checkd(ok, 1);
      `checkd(obj.x, 8'sd5);
      `checkd(obj.y, 8'sd6);

      obj.x.rand_mode(0);
      obj.y = 8'sd42;
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 8'sd5);
      `checkd(obj.y, 8'sd6);
      obj.x = 8'sd42;
      ok = obj.randomize();
      `checkd(ok, 0);
      `checkd(obj.x, 8'sd42);
      `checkd(obj.y, 8'sd6);

      obj.c_dist.constraint_mode(0);
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 8'sd42);
      `checkd(obj.y, 8'sd43);
    end
    begin
      automatic MixedSignOpen obj = new;
      int ok;
      for (int i = 0; i < 2; ++i) begin
        obj.upper = i[0];
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd(obj.x, 8'sd0);
        `checkd(obj.offset, 8'sd0);
      end
    end
    begin
      automatic SiblingStaged phased = new;
      automatic SiblingIndependent obj = new;
      int ok, clipped;
      clipped = 0;
      ok = phased.randomize();
      `checkd(ok, 1);
      `checkd((phased.after_tag != phased.tag), 1'b1);
      obj.srandom(37);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {8'd102, 8'd103}), 1'b1);
        clipped += int'(obj.x == 8'd102);
      end
      `checkd((clipped inside {[158:226]}), 1'b1);
    end
    begin
      automatic SignedEligible obj = new;
      int ok, clipped;
      clipped = 0;
      obj.srandom(53);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.s inside {-8'sd2, 8'sd3}), 1'b1);
        clipped += int'(obj.s == -8'sd2);
      end
      `checkd((clipped inside {[158:226]}), 1'b1);
    end
    begin
      automatic OpenRangeFallback obj = new;
      int ok;
      obj.requested = 8'd255;
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 8'd255);
      obj.requested = 8'd100;
      ok = obj.randomize();
      `checkd(ok, 0);
      `checkd(obj.x, 8'd255);
    end
    begin
      automatic WideOpenFallback obj = new;
      int ok;
      obj.requested = 80'd200;
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 80'd200);
      obj.requested = 80'd201;
      ok = obj.randomize();
      `checkd(ok, 0);
      `checkd(obj.x, 80'd200);
    end
    begin
      automatic WideBoundAdd obj = new;
      int ok;
      obj.b_input = 8'd45;
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.a, 8'd255);
      `checkd(obj.b, 8'd45);
      obj.b_input = 8'd46;
      ok = obj.randomize();
      `checkd(ok, 0);
      `checkd(obj.b, 8'd45);
    end
    begin
      automatic GlobalDistOwner obj = new;
      int clipped, ok;
      clipped = 0;
      obj.srandom(212);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd(obj.child.y, 8'd42);
        `checkd((obj.x inside {8'd102, 8'd103}), 1'b1);
        clipped += int'(obj.x == 8'd102);
      end
      `checkd((clipped inside {[158:226]}), 1'b1);
    end
    begin
      automatic InlineDistOperands obj = new;
      bit [7:0] x, offset;
      int class_clipped, std_clipped, ok;
      class_clipped = 0;
      std_clipped = 0;
      obj.srandom(213);
      repeat (256) begin
        ok = obj.randomize() with {
          offset == 8'd0;
          x >= 8'd102;
          (x + offset) dist {[8'd100:8'd102] := 1, 8'd103 :/ 1, 8'd99 := 65535};
        };
        `checkd(ok, 1);
        `checkd((obj.x inside {8'd102, 8'd103}), 1'b1);
        class_clipped += int'(obj.x == 8'd102);
        ok = std::randomize(x, offset) with {
          offset == 8'd0;
          x >= 8'd102;
          (x + offset) dist {[8'd100:8'd102] := 1, 8'd103 :/ 1, 8'd99 := 65535};
        };
        `checkd(ok, 1);
        `checkd((x inside {8'd102, 8'd103}), 1'b1);
        std_clipped += int'(x == 8'd102);
      end
      `checkd((class_clipped inside {[158:226]}), 1'b1);
      `checkd((std_clipped inside {[158:226]}), 1'b1);
    end
    begin
      automatic PointTrials obj = new;
      int ok;
      obj.srandom(317);
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.pick, 8'd127);
    end
  endtask

  initial begin
    if ($test$plusargs("dist_point_cases")) begin
      run_point_cases();
    end else begin
      begin
        automatic SoftDist obj = new;
        automatic int favored = 0;
        int ok;
        obj.srandom(143);
        repeat (64) begin
          ok = obj.randomize();
          `checkd(ok, 1);
          `checkd((obj.x inside {8'd3, 8'd9}), 1'b1);
          favored += int'(obj.x == 8'd3);
        end
        `checkd(favored >= 56, 1'b1);
        ok = obj.randomize() with {x == 7;};
        `checkd(ok, 1);
        `checkd(obj.x, 7);
        ok = obj.randomize() with {disable soft x; x == 8;};
        `checkd(ok, 1);
        `checkd(obj.x, 8);
      end
      begin
        automatic CompletedDraw obj = new;
        int ok;
        obj.srandom(421);
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.pick inside {4'd3, 4'd7}), 1'b1);
        `checkd((obj.payload[3] != '1), 1'b1);
      end
      // A no-op disable soft must preserve the same hard DIST weighting as a plain call.
      for (int mode = 0; mode < 2; ++mode) begin
        automatic HardForeach obj = new;
        int heavy, ok;
        heavy = 0;
        obj.srandom(780);
        repeat (6) begin
          if (mode == 0) ok = obj.randomize();
          else ok = obj.randomize() with {disable soft values;};
          `checkd(ok, 1);
          `checkd(obj.offset, 1'b0);
          heavy += $countones(obj.values);
        end
        `checkd((heavy inside {[640:747]}), 1'b1);
      end
      run_item_width();
      run_weight_arrays();
      run_dist_paths();
      run_wide_stats();
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
