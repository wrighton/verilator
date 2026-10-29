// DESCRIPTION: Test for IEEE 1800-2023 6.22.2 - valid array assignments with matching state types
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // 2-state arrays - assignment should work
  bit [7:0] arr_2state_a[3:0];
  bit [7:0] arr_2state_b[3:0];

  // 4-state arrays - assignment should work
  logic [7:0] arr_4state_a[3:0];
  logic [7:0] arr_4state_b[3:0];

  // Queues and dynamic arrays of 4-state elements (IEEE 1800-2023 7.6)
  logic [7:0] arr_4state_q[$];
  logic [7:0] arr_4state_d[];
  logic [7:0] arr_4state_2[1:0];
  int idx_q[$];

  initial begin
    // Initialize
    arr_2state_a[0] = 8'h10;
    arr_2state_a[1] = 8'h20;
    arr_2state_a[2] = 8'h30;
    arr_2state_a[3] = 8'h40;

    arr_4state_a[0] = 8'hA0;
    arr_4state_a[1] = 8'hB0;
    arr_4state_a[2] = 8'hC0;
    arr_4state_a[3] = 8'hD0;

    // Valid assignments: same state types
    arr_2state_b = arr_2state_a;  // 2-state to 2-state: OK
    arr_4state_b = arr_4state_a;  // 4-state to 4-state: OK

    // Verify
    if (arr_2state_b[0] !== 8'h10) $stop;
    if (arr_2state_b[3] !== 8'h40) $stop;
    if (arr_4state_b[0] !== 8'hA0) $stop;
    if (arr_4state_b[3] !== 8'hD0) $stop;

    arr_4state_q.push_back(8'h12);
    arr_4state_q.push_back(8'h34);
    arr_4state_2 = arr_4state_q;
    if (arr_4state_2[0] !== 8'h34) $stop;
    arr_4state_a[2:1] = arr_4state_q;
    arr_4state_d = arr_4state_q;
    if (arr_4state_d[1] !== 8'h34) $stop;
    idx_q = arr_4state_q.find_index with (item == 8'h34);
    if (idx_q[0] !== 1) $stop;

    $write("*-* All Coverage *-*\n");
    $finish;
  end
endmodule
