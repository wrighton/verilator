// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef struct {rand bit [6:0] v;} payload_t;

class Item;
  rand bit [6:0] v;
  bit [1:0] nr;
  Item next;
  struct {Item h;} sh;
  Item hq[$];
  rand bit f;
  rand payload_t payload;
endclass

class Sub;
  rand Item items[4];
endclass

class Holder;
  rand Item items[4];
  rand bit [1:0] k;
  rand bit [6:0] x;
  constraint not_c {!(items[k].v == 7'd5);}
  // Validity of the select is not required where an invalid index could satisfy the constraint
  constraint antecedent_c {(items[k].v == 7'd5) -> x == 7'd1;}
  constraint if_c {if (items[k].v > 7'd3) x < 7'd9;}
  constraint cond_c {x == ((items[k].v == 7'd2) ? 7'd1 : 7'd2);}
  constraint xor_c {(items[k].v == 7'd5) ^ (x == 7'd3);}
  constraint bool_c {items[k].f;}
  rand bit b;
  constraint nested_c {(items[k].v == 7'd5) == b;}
  constraint arm_c {x == (b ? items[k].v : 7'd2);}
  constraint soft_c {soft items[k].v == 7'd4;}
  rand bit [1:0] sel[2];
  constraint sum_c {sel.sum() with (int'(items[item].v)) < 20;}
  rand bit c;
  constraint or_value_c {((items[k].v == 7'd5) || b) == c;}
  constraint and_value_c {7'(((items[k].v == 7'd5) && b)) + x == 7'd2;}
  constraint struct_c {items[k].payload.v == 7'd5;}
  constraint equiv_c {(items[k].v == 7'd5) <-> (x == 7'd3);}
  constraint imp_value_c {(c -> (items[k].v == 7'd5)) == b;}
  function bit [6:0] pick(bit s, bit [6:0] a);
    return s ? a : 7'd0;
  endfunction
  // Under a state condition
  bit sb;
  constraint func_c {pick(sb, items[k].v) == 7'd5;}
  constraint state_arm_c {x == (sb ? items[k].v : 7'd2);}
  constraint not_imp_c {~(b -> (items[k].v == 7'd5));}
  constraint imp_bool_c {(c -> items[k].f) == b;}
  constraint or_bool_c {(items[k].f || c) == b;}
  constraint and_bool_c {(items[k].f && c) == b;}
  constraint nested_index_c {items[items[k].v[1:0]].v == 7'd5;}
  constraint state_index_c {items[items[k].nr].v == 7'd5;}
  // A state member too
  constraint state_if_c {if (items[k].nr == 2'd1) x == 7'd1;}
  constraint state_not_c {!(items[k].nr == 2'd2);}
  constraint state_handle_c {items[k].next != null;}
  constraint state_chain_c {items[k].next.nr == 2'd1;}
  rand Item items2[2][3];
  constraint state_2d_c {items2[k[0]][1].nr == 2'd1;}
  rand Item qitems[$];
  constraint state_queue_c {qitems[k].next != null;}
  rand Item aitems[int];
  rand int ak;
  constraint state_assoc_c {aitems[ak].next != null;}
  constraint state_struct_field_c {items[k].sh.h.nr == 2'd1;}
  constraint state_member_queue_c {items[k].hq[0].nr == 2'd1;}
  rand bit [1:0] rsel[2];
  constraint state_sum_c {rsel.sum() with (int'(items[item].nr)) < 4;}
  constraint state_sum_next_c {rsel.sum() with (int'(items[item].next.nr)) < 4;}
  int state_values[1];
  constraint state_nested_sum_c {
    rsel.sum(outer) with (state_values.sum(inner) with (int'(items[outer].nr))) == 2;
  }
  rand Sub sub;
  constraint state_path_c {x == 7'(sub.items[k].nr);}

  typedef struct {rand bit [1:0] x;} pick_t;
  rand pick_t picks[3];
  rand pick_t spicks[4];
  constraint state_struct_c {spicks[items[k].nr].x == 2'd1;}
  rand bit [1:0] pj;
  constraint struct_index_c {items[picks[pj].x].v == 7'd5;}
  rand pick_t picks2[2][2];
  rand bit pj2;
  constraint struct2_index_c {items[picks2[pj2][1].x].v == 7'd5;}
endclass

module t;
  initial begin
    automatic Holder h = new;
    void'(h.randomize());
  end
endmodule
