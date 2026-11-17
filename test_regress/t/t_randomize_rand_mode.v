// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Base;
  rand int m_one;

  task test1;
    m_one.rand_mode(0);
    `checkh(m_one.rand_mode(), 0);
    verify(0);

    m_one.rand_mode(1);
    `checkh(m_one.rand_mode(), 1);
    verify(1);
  endtask

  task verify(int mode_one);
    bit one_ne10 = '0;
    int v;
    if (m_one.rand_mode() != mode_one) $stop;
    for (int i = 0; i < 20; ++i) begin
      m_one = 10;
      v = randomize();
      if (m_one != 10) one_ne10 = 1'b1;
`ifdef TEST_VERBOSE
      $display("one=%0d(rand_mode=%0d)", m_one, mode_one);
`endif
    end
    if (mode_one != 0 && !one_ne10) $stop;
    if (mode_one == 0 && one_ne10) $stop;
  endtask

endclass

class Packet extends Base;
  rand int m_two;

  task test2;
    rand_mode(0);
    `checkh(m_one.rand_mode(), 0);
    `checkh(m_two.rand_mode(), 0);
    verify(0, 0);

    m_one.rand_mode(0);
    `checkh(m_one.rand_mode(), 0);
    m_two.rand_mode(1);
    `checkh(m_two.rand_mode(), 1);
    verify(0, 1);
  endtask

  task verify(int mode_one, int mode_two);
    bit one_ne10 = '0;
    bit two_ne10 = '0;
    int v;
    if (m_one.rand_mode() != mode_one) $stop;
    if (m_two.rand_mode() != mode_two) $stop;
    for (int i = 0; i < 20; ++i) begin
      m_one = 10;
      m_two = 10;
      v = randomize();
      if (m_one != 10) one_ne10 = 1'b1;
      if (m_two != 10) two_ne10 = 1'b1;
`ifdef TEST_VERBOSE
      $display("one=%0d(rand_mode=%0d) two=%0d(rand_mode=%0d)", m_one, mode_one, m_two, mode_two);
`endif
    end
    if (mode_one != 0 && !one_ne10) $stop;
    if (mode_two != 0 && !two_ne10) $stop;
    if (mode_one == 0 && one_ne10) $stop;
    if (mode_two == 0 && two_ne10) $stop;
  endtask

endclass

class ModeOther;
  rand bit [6:0] x;
endclass

// Handles of the current class, static or not, and of another class
class ModeSelf;
  static ModeSelf self;
  rand bit [6:0] v;
  ModeOther o;
  ModeOther arr[2];
  function new;
    o = new;
    foreach (arr[i]) arr[i] = new;
  endfunction
  task freeze;
    self.v.rand_mode(0);
    o.x.rand_mode(0);
    arr[1].x.rand_mode(0);
  endtask
endclass

class ModeElement;
  rand bit [6:0] v;
  rand bit [14:0] w;
  ModeElement peers[2];
  int bare_calls;
  int wide_calls;

  function bit [1:0] wide_mode;
    bit [1:0] value;
    value = {1'b1, wide_calls[0]};
    ++wide_calls;
    return value;
  endfunction

  function bit bare_mode;
    ++bare_calls;
    return 1;
  endfunction

  task check_peer;
    ModeElement other;
    bit flag;
    flag = 0;
    rand_mode(flag);
    `checkh(v.rand_mode(), 0);
    `checkh(w.rand_mode(), 0);
    rand_mode(bare_mode());
    `checkh(bare_calls, 1);
    `checkh(v.rand_mode(), 1);
    `checkh(w.rand_mode(), 1);
    other = new;
    other.rand_mode(0);
    `checkh(v.rand_mode(), 1);
    `checkh(other.v.rand_mode(), 0);
    `checkh(other.w.rand_mode(), 0);
    other.v.rand_mode(1);
    `checkh(v.rand_mode(), 1);
    `checkh(other.v.rand_mode(), 1);
    `checkh(other.w.rand_mode(), 0);
    this.rand_mode(0);
    `checkh(v.rand_mode(), 0);
    `checkh(w.rand_mode(), 0);
    this.rand_mode(1);
    `checkh(v.rand_mode(), 1);
    `checkh(w.rand_mode(), 1);
    foreach (peers[i]) peers[i] = new;
    peers[0].rand_mode(0);
    `checkh(v.rand_mode(), 1);
    `checkh(peers[0].v.rand_mode(), 0);
    `checkh(peers[0].w.rand_mode(), 0);
    `checkh(peers[1].v.rand_mode(), 1);
    peers[1].v.rand_mode(0);
    `checkh(v.rand_mode(), 1);
    `checkh(peers[1].v.rand_mode(), 0);
    `checkh(peers[1].w.rand_mode(), 1);
    for (int i = 0; i < 4; ++i) begin
      bit [1:0] wide_flag;
      wide_flag = {1'b1, i[0]};
      // The truncation warning is checked separately in t_randomize_mode_width.
      // verilator lint_off WIDTHTRUNC
      rand_mode(wide_flag);
      `checkh(v.rand_mode(), int'(bit'(wide_flag)));
      `checkh(w.rand_mode(), int'(bit'(wide_flag)));
      rand_mode(wide_mode());
      // verilator lint_on WIDTHTRUNC
      `checkh(wide_calls, i + 1);
      `checkh(v.rand_mode(), int'(i[0]));
      `checkh(w.rand_mode(), int'(i[0]));
      // Method-call wider arguments are a separate fix; these are bit-typed controls.
      other.rand_mode(bit'(wide_flag));
      peers[1].rand_mode(bit'(wide_flag));
      v.rand_mode(bit'(wide_flag));
      `checkh(other.v.rand_mode(), int'(i[0]));
      `checkh(peers[1].w.rand_mode(), int'(i[0]));
      `checkh(v.rand_mode(), int'(i[0]));
    end
  endtask
endclass

typedef ModeElement mode_element_t;

class ModeConstraint;
  rand bit [6:0] x;
  constraint c_lo {x < 4;}
  constraint c_hi {x < 8;}

  task check_implicit;
    c_lo.constraint_mode(0);
    `checkh(c_lo.constraint_mode(), 0);
    c_lo.constraint_mode(1);
    `checkh(c_lo.constraint_mode(), 1);
  endtask
endclass

class ModeCfg;
  mode_element_t regs[2][3];
  mode_element_t q[$];
  mode_element_t dyn[];
  mode_element_t assoc[string];
  mode_element_t wild[*];
  mode_element_t bounds[1:2][4:3];
  ModeConstraint constraints[];
  ModeConstraint queue_constraints[$];
  rand bit control;
  int index_calls;
  int argument_calls;

  function new;
    foreach (regs[i, j]) regs[i][j] = new;
    repeat (3) begin
      automatic mode_element_t r = new;
      q.push_back(r);
    end
    dyn = new[2];
    foreach (dyn[i]) dyn[i] = new;
    foreach (bounds[i, j]) bounds[i][j] = new;
    assoc["first"] = new;
    assoc["second"] = new;
    wild[1] = new;
    constraints = new[2];
    foreach (constraints[i]) constraints[i] = new;
    repeat (2) begin
      automatic ModeConstraint c = new;
      queue_constraints.push_back(c);
    end
  endfunction

  function void setup;
    foreach (regs[ii, jj]) regs[ii][jj].rand_mode(0);
    foreach (q[rr]) q[rr].rand_mode(0);
  endfunction

  function int next_index;
    ++index_calls;
    return 1;
  endfunction

  function bit next_mode;
    ++argument_calls;
    return argument_calls != 1;
  endfunction

  function mode_element_t get_element;
    ++index_calls;
    return dyn[0];
  endfunction

  task check_modes;
    mode_element_t first;
    bit changed;
    int index;
    string key;

    setup();
    foreach (regs[ii, jj]) begin
      `checkh(regs[ii][jj].v.rand_mode(), 0);
      `checkh(regs[ii][jj].w.rand_mode(), 0);
    end
    foreach (q[rr]) begin
      `checkh(q[rr].v.rand_mode(), 0);
      `checkh(q[rr].w.rand_mode(), 0);
    end
    foreach (regs[ii, jj]) begin
      regs[ii][jj].rand_mode(1);
      `checkh(regs[ii][jj].v.rand_mode(), 1);
    end
    index = 1;
    regs[index][index].rand_mode(next_mode());
    `checkh(argument_calls, 1);
    `checkh(regs[1][1].v.rand_mode(), 0);
    `checkh(regs[1][1].w.rand_mode(), 0);
    `checkh(regs[1][0].v.rand_mode(), 1);
    `checkh(regs[0][1].v.rand_mode(), 1);

    argument_calls = 0;
    q[next_index()].rand_mode(next_mode());
    `checkh(index_calls, 1);
    `checkh(argument_calls, 1);
    `checkh(q[1].w.rand_mode(), 0);
    foreach (q[rr]) q[rr].rand_mode(1);
    q[index].v.rand_mode(0);
    `checkh(q[index].v.rand_mode(), 0);
    `checkh(q[index].w.rand_mode(), 1);
    `checkh(q[0].v.rand_mode(), 1);
    q[$].rand_mode(0);
    `checkh(q[$].v.rand_mode(), 0);
    `checkh(q[$].w.rand_mode(), 0);
    first = q[0];
    q.pop_front().rand_mode(0);
    `checkh(q.size(), 2);
    `checkh(first.v.rand_mode(), 0);
    `checkh(first.w.rand_mode(), 0);

    index_calls = 0;
    argument_calls = 0;
    dyn[next_index()].rand_mode(next_mode());
    `checkh(index_calls, 1);
    `checkh(argument_calls, 1);
    `checkh(dyn[1].v.rand_mode(), 0);
    `checkh(dyn[0].v.rand_mode(), 1);
    get_element().rand_mode(0);
    `checkh(index_calls, 2);
    `checkh(dyn[0].w.rand_mode(), 0);

    key = "first";
    assoc[key].rand_mode(0);
    `checkh(assoc[key].v.rand_mode(), 0);
    `checkh(assoc["second"].v.rand_mode(), 1);
    wild[index].rand_mode(0);
    `checkh(wild[index].w.rand_mode(), 0);
    foreach (bounds[i, j]) begin
      bounds[i][j].rand_mode(0);
      `checkh(bounds[i][j].v.rand_mode(), 0);
      `checkh(bounds[i][j].w.rand_mode(), 0);
    end

    dyn[0].v = 7'h35;
    dyn[0].w = 15'h1234;
    repeat (20) begin
      int randomize_result;
      randomize_result = dyn[0].randomize();
      `checkh(randomize_result, 1);
      `checkh(dyn[0].v, 7'h35);
      `checkh(dyn[0].w, 15'h1234);
    end
    dyn[0].v.rand_mode(1);
    `checkh(dyn[0].v.rand_mode(), 1);
    `checkh(dyn[0].w.rand_mode(), 0);
    changed = 0;
    repeat (20) begin
      int randomize_result;
      randomize_result = dyn[0].randomize();
      `checkh(randomize_result, 1);
      if (dyn[0].v != 7'h35) changed = 1;
      `checkh(dyn[0].w, 15'h1234);
    end
    `checkh(changed, 1);
    dyn[0].rand_mode(1);
    dyn[0].check_peer();
    dyn[1].v.rand_mode(1);
    dyn[0].rand_mode(0);
    index_calls = 0;
    dyn[0].rand_mode(bit'(dyn[next_index()].v.rand_mode()));
    `checkh(index_calls, 1);
    `checkh(dyn[0].v.rand_mode(), 1);
    `checkh(dyn[0].w.rand_mode(), 1);
    foreach (constraints[i]) begin
      constraints[i].check_implicit();
      `checkh(constraints[i].c_lo.constraint_mode(), 1);
      constraints[i].c_lo.constraint_mode(bit'(i % 2));
      `checkh(constraints[i].c_lo.constraint_mode(), i % 2);
    end
    foreach (queue_constraints[i]) begin
      `checkh(queue_constraints[i].c_lo.constraint_mode(), 1);
      queue_constraints[i].c_lo.constraint_mode(bit'(i % 2));
      `checkh(queue_constraints[i].c_lo.constraint_mode(), i % 2);
    end
    constraints[0].constraint_mode(1);
    index_calls = 0;
    argument_calls = 0;
    constraints[next_index()].constraint_mode(next_mode());
    `checkh(index_calls, 1);
    `checkh(argument_calls, 1);
    `checkh(constraints[1].c_lo.constraint_mode(), 0);
    `checkh(constraints[1].c_hi.constraint_mode(), 0);
    `checkh(constraints[0].c_lo.constraint_mode(), 1);
    `checkh(constraints[0].c_hi.constraint_mode(), 1);
    begin
      ModeConstraint first_constraint;
      first_constraint = queue_constraints[0];
      queue_constraints.pop_front().constraint_mode(0);
      `checkh(queue_constraints.size(), 1);
      `checkh(first_constraint.c_lo.constraint_mode(), 0);
      `checkh(first_constraint.c_hi.constraint_mode(), 0);
      `checkh(queue_constraints[0].c_lo.constraint_mode(), 1);
      `checkh(queue_constraints[0].c_hi.constraint_mode(), 1);
    end
    control.rand_mode(0);
    `checkh(control.rand_mode(), 0);
  endtask
endclass

module t;

  Packet p;

  int v;

  initial begin
    automatic ModeCfg cfg = new;
    cfg.regs[0][0].rand_mode(1);
    `checkh(cfg.regs[0][0].v.rand_mode(), 1);
    p = new;

    cfg.check_modes();

    p.test1();
    p.test2();

    // IEEE: function void object[.random_variable].rand_mode(bit on_off);
    // IEEE: function int object.random_variable.rand_mode();
    // Not legal to get current rand() value on a class-only call

    // We call rand_mode here too becuase the parsing is different from that
    // called from the class itself
    p.m_one.rand_mode(0);
    `checkh(p.m_one.rand_mode(), 0);
    p.m_two.rand_mode(0);
    `checkh(p.m_two.rand_mode(), 0);
    p.verify(0, 0);

    p.m_one.rand_mode(0);
    `checkh(p.m_one.rand_mode(), 0);
    p.m_two.rand_mode(1);
    `checkh(p.m_two.rand_mode(), 1);
    p.verify(0, 1);

    p.rand_mode(1);
    p.verify(1, 1);

    p.rand_mode(0);
    p.verify(0, 0);

    begin
      // Indices in the receiver are only read
      Packet pa[2];
      int idxu[2];
      int idxa[string];
      int idxw[*];
      int idxd[];
      int idxq[$];
      pa[0] = new;
      pa[idxu[1]].m_one.rand_mode(0);
      pa[idxa["k"]].m_one.rand_mode(0);
      pa[idxw["k"]].m_one.rand_mode(0);
      pa[idxd[0]].m_one.rand_mode(0);
      pa[idxq[0]].m_one.rand_mode(0);
      `checkh(pa[0].m_one.rand_mode(), 0);
      `checkh(idxa.size(), 0);
      `checkh(idxw.size(), 0);
      `checkh(idxd.size(), 0);
      `checkh(idxq.size(), 0);
    end

    begin
      // Each call freezes the variable of the object it selects
      ModeSelf a;
      ModeSelf b;
      int ok;
      a = new;
      b = new;
      ModeSelf::self = b;
      b.v = 7'd77;
      a.o.x = 7'd55;
      a.arr[1].x = 7'd33;
      a.freeze();
      `checkh(a.v.rand_mode(), 1);
      `checkh(b.v.rand_mode(), 0);
      `checkh(a.o.x.rand_mode(), 0);
      `checkh(a.arr[0].x.rand_mode(), 1);
      `checkh(a.arr[1].x.rand_mode(), 0);
      repeat (10) begin
        ok = b.randomize();
        `checkh(ok, 1);
        `checkh(b.v, 7'd77);
        ok = a.o.randomize();
        `checkh(ok, 1);
        `checkh(a.o.x, 7'd55);
        ok = a.arr[1].randomize();
        `checkh(ok, 1);
        `checkh(a.arr[1].x, 7'd33);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
