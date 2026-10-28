// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef interface class IfFwd;
typedef interface class IfEarly;

class ClsBad implements IfFwd;  // <--- Bad: IEEE 1800-2023 8.26.4
endclass

interface class IfBad extends IfFwd;  // <--- Bad: IEEE 1800-2023 8.26.4
endclass

interface class IfFwd;
endclass

interface class IfEarly;
endclass

class ClsOk implements IfEarly;
endclass

module t;
  ClsBad c1;
  ClsOk c2;
endmodule
