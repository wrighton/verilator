// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub #(
    parameter int LIST[3] = '{0, 0, 0},
    parameter int VALUE = 0
);
  localparam bit IS_IN = VALUE inside {LIST};
endmodule

module t;

  localparam int CHECKLIST_P[2:0] = '{0, 1, 2};

  localparam HIT_LP = 1;
  localparam MISS_LP = 4;
  localparam HIT_INSIDE = HIT_LP inside {CHECKLIST_P};
  localparam MISS_INSIDE = MISS_LP inside {CHECKLIST_P};

  localparam int ASC_P[3] = '{1, 3, 5};
  localparam logic [3:0] WILD_P[2] = '{4'b10x1, 4'b0110};
  localparam string NAMES_P[2] = '{"ab", "cd"};
  localparam real REALS_P[2] = '{1.5, 2.5};

  localparam bit ASC_HIT = 5 inside {ASC_P};
  localparam bit ASC_MISS = 4 inside {ASC_P};
  localparam bit MIXED_HIT = 7 inside {ASC_P, 7, [10 : 12]};
  localparam bit RANGE_HIT = 11 inside {ASC_P, [10 : 12]};
  localparam bit WILD_HIT = 4'b1011 inside {WILD_P};
  localparam bit WILD_MISS = 4'b1111 inside {WILD_P};
  localparam bit NAME_HIT = "cd" inside {NAMES_P};
  localparam bit NAME_MISS = "ef" inside {NAMES_P};
  localparam bit REAL_HIT = 2.5 inside {REALS_P};
  localparam bit REAL_MISS = 2.0 inside {REALS_P};

  // Compared at the width of the wider of value and element, a narrower element extended
  // as signed only if both are (IEEE 1800-2023 11.8.2)
  localparam bit [2:0] NARROW_P[2] = '{3'd1, 3'd2};
  localparam logic signed [2:0] SNARROW_P[2] = '{-3'sd1, 3'sd2};
  /* verilator lint_off WIDTH */
  localparam bit WIDE_MISS = 4'd9 inside {NARROW_P};
  localparam bit WIDE_HIT = 4'd2 inside {NARROW_P};
  localparam bit SIGNED_HIT = -4'sd1 inside {SNARROW_P};
  localparam bit UNSIGNED_MISS = 4'd15 inside {SNARROW_P};
  localparam bit UNSIGNED_HIT = 4'd7 inside {SNARROW_P};
  // An x sign bit of a signed element extends as x, matching any value bits there
  localparam logic signed [2:0] SWILD_P[1] = '{3'sbx00};
  localparam bit SWILD_HIT = 4'sd4 inside {SWILD_P};
  localparam bit SWILD_LIST_HIT = 4'sd4 inside {SWILD_P[0]};
  // Against unsigned elements a signed value is not sign-extended, nor is a narrower one
  localparam bit [3:0] UNARROW_P[2] = '{4'd12, 4'd0};
  localparam bit NEG_HIT = -4'sd4 inside {UNARROW_P};
  localparam bit NARROW_VALUE_MISS = 3'sb111 inside {UNARROW_P};
  /* verilator lint_on WIDTH */

  sub #(.LIST('{4, 5, 6}), .VALUE(6)) u_hit ();
  sub #(.LIST('{4, 5, 6}), .VALUE(7)) u_miss ();

  if (3 inside {ASC_P}) begin : g_hit
    localparam bit FOUND = 1;
  end else begin : g_hit
    localparam bit FOUND = 0;
  end
  if (2 inside {ASC_P}) begin : g_miss
    localparam bit FOUND = 1;
  end else begin : g_miss
    localparam bit FOUND = 0;
  end

  initial begin
    if (HIT_INSIDE != 1) $stop;
    if (MISS_INSIDE != 0) $stop;
    if (ASC_HIT != 1) $stop;
    if (ASC_MISS != 0) $stop;
    if (MIXED_HIT != 1) $stop;
    if (RANGE_HIT != 1) $stop;
    if (WILD_HIT != 1) $stop;
    if (WILD_MISS != 0) $stop;
    if (NAME_HIT != 1) $stop;
    if (NAME_MISS != 0) $stop;
    if (REAL_HIT != 1) $stop;
    if (REAL_MISS != 0) $stop;
    if (WIDE_MISS != 0) $stop;
    if (WIDE_HIT != 1) $stop;
    if (SIGNED_HIT != 1) $stop;
    if (UNSIGNED_MISS != 0) $stop;
    if (UNSIGNED_HIT != 1) $stop;
    if (SWILD_HIT != 1) $stop;
    if (SWILD_LIST_HIT != 1) $stop;
    if (NEG_HIT != 1) $stop;
    if (NARROW_VALUE_MISS != 0) $stop;
    if (u_hit.IS_IN != 1) $stop;
    if (u_miss.IS_IN != 0) $stop;
    if (g_hit.FOUND != 1) $stop;
    if (g_miss.FOUND != 0) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
