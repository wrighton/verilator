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

  int assocIntA[int];
  int assocStrA[string];
  int assocNestA[string][int];
  int assocNestB[string][byte];
  int assocIntegerA[integer];
  initial begin
    assocStrA = assocIntA;
    assocNestA = assocNestB;
    assocIntA = assocIntegerA;
  end

  class Cls1;
  endclass
  class Cls2;
  endclass
  int assocRealA[real];
  int assocCls1A[Cls1];
  int assocCls2A[Cls2];
  real dynRealA[];
  int dynIntA[];
  logic [1:0][3:0] dynPackA[];
  initial begin
    assocIntA = assocStrA;
    assocRealA = assocIntA;
    assocCls1A = assocCls2A;
    assocIntA = assocCls1A;
    assocCls1A = assocIntA;
    dynRealA = dynIntA;
    dynRealA = dynPackA;
    dynPackA = dynRealA;
  end

  // Expressions other than variables
  class Holder;
    int assocByteA[byte];
    real dynRealA[];
  endclass
  typedef byte bytes_t[];
  function automatic bytes_t getBytes();
    return '{1, 2};
  endfunction
  Holder holder;
  initial begin
    holder = new;
    assocIntA = holder.assocByteA;
    holder.dynRealA = dynIntA;
    dynIntA = getBytes();
    holder.dynRealA = nonAggregate;
    nonAggregate = holder.dynRealA;
    {nonAggregate, unpackedA[0]} = holder.dynRealA;
    {nonAggregate, unpackedA[0]} = getBytes();
    {nonAggregate, unpackedA[0]} = dynIntA;
  end
  real realU[2];
  int intU[4];
  initial realU = intU[0:1];

  // Port connections other than variables
  typedef struct {
    int m[2];
  } portHolder_t;
  portHolder_t portHolder;
  int portRows[2][2];
  sub u_sel (.p(portRows[0]));
  sub u_mem (.p(portHolder.m));
endmodule

module sub (
    input logic [31:0] p[2]
);
endmodule
