// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Register model: a register randomized only through a base handle, and as a
// rand member of a block
class Obj;
endclass

class Field;
  rand bit [7:0] value;
  constraint c_value {value inside {[1 : 200]};}
endclass

class Reg extends Obj;
  rand Field f;
  function new;
    f = new;
  endfunction
endclass

class Block;
  rand Reg r;
  function new;
    r = new;
  endfunction
endclass

// Three levels of rand members, leaf fields declared in a base class, the
// outermost object randomized through a base handle and through its own
class coord_id;
  rand int unsigned m_xcoord;
  rand int unsigned m_ycoord;
endclass

class noc_coord_id extends coord_id;
  constraint c_range {
    m_xcoord < 8;
    m_ycoord < 8;
  }
endclass

class noc_requestor;
  rand noc_coord_id m_coord;
  function new();
    m_coord = new;
  endfunction
endclass

class noc_path_cfg;
  rand noc_requestor m_initiator;
  rand noc_requestor m_target;
  function new();
    m_initiator = new;
    m_target = new;
  endfunction
  constraint c_diff {
    !((m_initiator.m_coord.m_xcoord == m_target.m_coord.m_xcoord)
      && (m_initiator.m_coord.m_ycoord == m_target.m_coord.m_ycoord));
  }
endclass

class seq_cfg_base;
  rand int unsigned m_vc;
endclass

class sist_seq_cfg extends seq_cfg_base;
  rand noc_path_cfg m_path_cfg;
  function new();
    m_path_cfg = new;
  endfunction
endclass

class dcnoc_seq_cfg extends sist_seq_cfg;
endclass

module t;
  function automatic void check_path(sist_seq_cfg c);
    `checkd(c.m_path_cfg.m_initiator.m_coord.m_xcoord < 8, 1'b1);
    `checkd(c.m_path_cfg.m_initiator.m_coord.m_ycoord < 8, 1'b1);
    `checkd(c.m_path_cfg.m_target.m_coord.m_xcoord < 8, 1'b1);
    `checkd(c.m_path_cfg.m_initiator.m_coord.m_xcoord == c.m_path_cfg.m_target.m_coord.m_xcoord
            && c.m_path_cfg.m_initiator.m_coord.m_ycoord
            == c.m_path_cfg.m_target.m_coord.m_ycoord, 1'b0);
  endfunction

  initial begin
    automatic Block blk = new;
    automatic Reg rg = new;
    automatic Obj o = rg;
    automatic sist_seq_cfg sc = new;
    automatic dcnoc_seq_cfg dc = new;
    automatic seq_cfg_base sb;
    automatic int ok;
    automatic int changed = 0;
    automatic bit [7:0] prev;
    repeat (20) begin
      ok = blk.randomize();
      `checkd(ok, 1);
      `checkd(blk.r.f.value inside {[1 : 200]}, 1'b1);
      prev = rg.f.value;
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(rg.f.value inside {[1 : 200]}, 1'b1);
      if (rg.f.value != prev) ++changed;
      sb = sc;
      ok = sb.randomize();
      `checkd(ok, 1);
      check_path(sc);
      sb = dc;
      ok = sb.randomize();
      `checkd(ok, 1);
      check_path(dc);
      ok = dc.randomize();
      `checkd(ok, 1);
      check_path(dc);
    end
    `checkd(changed > 10, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
