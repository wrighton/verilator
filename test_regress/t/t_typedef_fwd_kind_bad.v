// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef struct ok_struct_t;
  typedef struct {int a;} ok_struct_t;
  typedef class OkCls;
  class OkCls;
  endclass
  typedef class ok_cls_t;
  typedef OkCls ok_cls_t;

  typedef struct struct_int_t;  // BAD: kind differs
  typedef int struct_int_t;
  typedef enum enum_struct_t;  // BAD: kind differs
  typedef struct {int a;} enum_struct_t;
  typedef union union_enum_t;  // BAD: kind differs
  typedef enum {A} union_enum_t;
  typedef class cls_int_t;  // BAD: kind differs
  typedef int cls_int_t;
  typedef struct StructCls;  // BAD: kind differs
  class StructCls;
  endclass
endmodule
