// DESCRIPTION: Verilator: Verilog Test module for SystemVerilog
//
// Assignment compatibility test.
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

typedef struct packed {
  int a;
  int b;
} struct_t;

typedef struct {
  int a;
  int b;
} ustruct_t;

typedef union {
  int a;
  int b;
} uunion_t;

module t;

  logic unpackedA[2];
  logic unpackedB[3];
  logic unpackedC[3][2];
  logic unpackedD[4][2];
  struct_t unpackedE[4][2];
  logic nonAggregate;
  logic assocArrayA[string];
  logic queueA[$];
  bit queueB[$];
  logic unpackedF[3] = unpackedA;
  bit unpackedG[2] = unpackedB[0:1];

  assign unpackedB = unpackedA;
  assign unpackedB = unpackedC;
  assign unpackedD = unpackedC;
  assign unpackedE = unpackedD;
  assign nonAggregate = unpackedA;
  assign unpackedA = assocArrayA;
  assign queueA = queueB;

  ustruct_t ustructA = 7;
  ustruct_t ustructB[2] = '{7, 8};
  ustruct_t ustructC;
  ustruct_t ustructD[2][2] = '{default: '{7, 8}};
  assign ustructC = '0;
  ustruct_t ustructE = '0;  // Issue #7460
  uunion_t uunionA = 7;

  typedef logic row3_t[3];
  typedef logic row2_t[2];
  row3_t rows3[2];
  row2_t rows2[2];
  assign rows3 = rows2;

  // Singular values assigned to unpacked arrays
  int queueI[$] = 5;
  int queueQ[$][$] = '{5};
  typedef int queue_t[$];
  queue_t queueT = 5;
  initial begin
    int dynI[];
    int assocI[int];
    int fixedI[3];
    real queueR[$];
    string queueS[$];
    string str;
    queueI = 5;
    queueQ = '{queueI, nonAggregate};
    dynI = nonAggregate;
    assocI = 5;
    fixedI = 5;
    queueR = 1.5;
    queueS = str;
  end
  sub u_sub (.queueP(5));
endmodule

module sub (
    input int queueP[$]
);
endmodule
