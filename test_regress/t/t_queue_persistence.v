// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

localparam int N = 4096;

class Item;
  int v;
endclass

// Elements removed, or containers replaced, while passed by reference continue to exist as
// outdated references; changes through them are not seen in the container (IEEE 1800-2023 13.5.2)
typedef struct {
  int a;
  logic [69:0] w;
} pair_t;

// Whether removing an element passed by reference from an end of a queue leaves the references
// to the remaining elements bound, which depends on the C++ library (see verilated_types.h)
function automatic bit kept_bound();
`ifdef VERILATOR
  return $c32("VL_REF_SLOTS") != 0;
`else
  return 1;
`endif
endfunction

class Holder;
  int q[$];
  int d[];
  int qq[$][$];

  function void fill();
    q.delete();
    for (int j = 0; j < N; ++j) q.push_back(j);
  endfunction
  function bit unchanged();
    foreach (q[j]) if (q[j] != j) return 0;
    return q.size() == N;
  endfunction

  function int bump_delete(ref int r);
    fill();
    r = r + 1;
    return r;
  endfunction
  function int bump_pop(ref int r, input int npop);
    repeat (npop) void'(q.pop_front());
    q.push_front(-7);
    r = r + 1;
    return r;
  endfunction
  function void bump_assign(ref int r);
    q = q[1:$];
    r = -1;
  endfunction
  function int bump_erase(ref int r, input int index);
    q.delete(index);
    r = r + 1;
    return r;
  endfunction
  function int bump_insert(ref int r, input int index, input int count);
    repeat (count) q.insert(index, -5);
    r = r + 1;
    return r;
  endfunction
  function int bump_two(ref int a, ref int b);
    q.insert(2000, -5);
    q.delete(2500);
    a = a + 1;
    b = b + 1;
    return a + b;
  endfunction
  function int bump_pop_back(ref int r);
    void'(q.pop_back());
    q.push_back(-7);
    r = r + 1;
    return r;
  endfunction
  function int bump_copy(ref int r, const ref int src[$]);
    q = src;
    r = r + 1;
    return r;
  endfunction
  int qb[$:N - 1];
  function int bump_bounded(ref int r);
    qb.push_front(-1);
    void'(qb.pop_front());
    qb.push_back(-9);
    r = r + 1;
    return r;
  endfunction
  function int bump_bounded_copy(ref int r);
    qb = q;
    r = -r;
    return r;
  endfunction
  logic [69:0] w[$];
  function logic [69:0] bump_wide(ref logic [69:0] r);
    w.delete();
    r = r + 1;
    return r;
  endfunction
  int d2[];
  function int bump_dcopy(ref int r);
    d = d2;
    r = r + 1;
    return r;
  endfunction
  function int bump_new(ref int r);
    d = new[2 * N];
    r = r + 1;
    return r;
  endfunction
  function int bump_shrink(ref int r);
    d = new[N](d);
    r = r + 1;
    return r;
  endfunction
  function int bump_outer(ref int r);
    qq.delete();
    r = r + 1;
    return r;
  endfunction
  function int bump_shift(ref int r, input int index);
    qq.insert(index, '{});
    qq.delete();
    r = r + 1;
    return r;
  endfunction
  function int bump_pop_other(ref int a, ref int b);
    void'(q.pop_front());
    a = a + 1;
    b = b + 1;
    return a;
  endfunction
  function int bump_drain(ref int r);
    repeat (N - 1) void'(q.pop_front());
    q.push_front(-1);
    r = r + 1;
    return r;
  endfunction
  function int bump_pop_two(ref int a, ref int b);
    void'(q.pop_front());
    void'(q.pop_front());
    q.delete();
    a = a + 1;
    b = b + 1;
    return a + b;
  endfunction
  function int bump_last(ref int r);
    void'(q.pop_front());
    q.push_back(8);
    q.push_front(9);
    r = r + 1;
    return r;
  endfunction
  function int bump_pop_assign(ref int r);
    void'(q.pop_front());
    q = '{5, 6, 7};
    r = r + 1;
    return r;
  endfunction
  function int bump_erase_other(ref int a, ref int b, input int index);
    q.delete(index);
    a = a + 1;
    b = b + 1;
    return a;
  endfunction
  function int bump_clear_inner(ref int b);
    q.delete();
    b = b + 1;
    return b;
  endfunction
  function int bump_clear_outer(ref int a);
    void'(q.pop_front());
    `checkd(bump_clear_inner(q[100]), 102);
    a = a + 1;
    return a;
  endfunction
  function int bump_pop_insert(ref int a, ref int b, input int index);
    void'(q.pop_front());
    q.insert(index, -5);
    a = a + 1;
    return a;
  endfunction
  function int bump_inner_q(ref int r[$], input bit front);
    if (front) void'(qq.pop_front());
    else void'(qq.pop_back());
    qq.delete();
    return r.size() + r[5];
  endfunction
  Item iq[$];
  function void bump_item(ref Item r);
    void'(iq.pop_front());
    iq.delete();
    r.v = r.v + 1;
    r = null;
  endfunction
  function void bump_reuse_front(ref int removed, ref int survivor);
    void'(q.pop_front());
    q.push_front(99);
    removed = 7;
    survivor = 42;
  endfunction
  function void bump_reuse_back(ref int removed, ref int survivor);
    void'(q.pop_back());
    q.push_back(99);
    removed = 7;
    survivor = 42;
  endfunction
  int qb3[$:3];
  function void bump_reuse_bound(ref int survivor, ref int removed);
    qb3.push_front(9);
    void'(qb3.pop_front());
    qb3.push_back(5);
    removed = 7;
    survivor = 42;
  endfunction
  // As a FIFO: the element passed by reference popped from one end, an element pushed at the
  // other
  function void bump_fifo(ref int head, ref int other, input bit back);
    if (back) begin
      void'(q.pop_back());
      q.push_front(-1);
    end
    else begin
      void'(q.pop_front());
      q.push_back(-1);
    end
    head = -7;
    other = other + 1;
  endfunction
  function int bump_bounded_two(ref int a, ref int b);
    qb.push_front(-1);
    a = a + 1;
    b = b + 1;
    return a + b;
  endfunction
  int qr[$][4];
  pair_t qs[$];
  int da[][4];
  function int bump_sub(ref int a, ref int b, ref int c);
    void'(qr.pop_front());
    repeat (N - 1) void'(qs.pop_front());
    da.delete();
    a = a + 1;
    b = b + 1;
    c = c + 1;
    return a + b + c;
  endfunction
  function int bump_sub_kept(ref int a, ref logic [69:0] w);
    void'(qr.pop_front());
    void'(qs.pop_back());
    a = a + 1;
    w = w + 1;
    return a;
  endfunction
  task bump_sub_later(ref int r);
    #1;
    r = r + 1;
    `checkd(r, 3);
  endtask
  task bump_later(ref int r);
    #1;
    r = r + 1;
    `checkd(r, 3001);
  endtask
endclass

module t;
  initial begin  // Queue deleted and refilled by the callee
    automatic Holder h = new;
    h.fill();
    `checkd(h.bump_delete(h.q[3000]), 3001);
    `checkd(h.unchanged(), 1);
  end

  initial begin  // The element itself popped, then another element popped
    automatic Holder h = new;
    h.fill();
    `checkd(h.bump_pop(h.q[3000], 3001), 3001);
    `checkd(h.q.size(), N - 3000);
    `checkd(h.q[0], -7);
    `checkd(h.q[1], 3001);
    // A reference to an element that stays in the queue follows it
    `checkd(h.bump_pop(h.q[1000], 10), 4001);
    `checkd(h.q[991], 4001);
  end

  initial begin  // Queue updated by assignment
    automatic Holder h = new;
    h.fill();
    h.bump_assign(h.q[3000]);
    `checkd(h.q.size(), N - 1);
    `checkd(h.q[2999], 3000);
    `checkd(h.q[3000], 3001);
  end

  initial begin  // The element itself deleted by index, or popped from the back
    automatic Holder h = new;
    h.fill();
    `checkd(h.bump_erase(h.q[3000], 3000), 3001);
    `checkd(h.q.size(), N - 1);
    `checkd(h.q[3000], 3001);
    h.fill();
    `checkd(h.bump_pop_back(h.q[$]), N);
    `checkd(h.q.size(), N);
    `checkd(h.q[N - 1], -7);
  end

  initial begin  // Wide elements received by a typeless mailbox
    automatic Holder h = new;
    automatic mailbox mb = new;
    automatic logic [69:0] v = 70'h2_1234_5678_9abc_def0;
    for (int j = 0; j < N; ++j) h.w.push_back(0);
    mb.put(v);
    mb.get(h.w[3000]);
    `checkh(h.w[3000], v);
  end

  initial begin  // Wide elements
    automatic Holder h = new;
    for (int j = 0; j < N; ++j) h.w.push_back(70'(j) << 40);
    `checkh(h.bump_wide(h.w[3000]), (70'(3000) << 40) + 1);
    `checkd(h.w.size(), 0);
  end

  initial begin  // Elements inserted or deleted before or after the element
    automatic Holder h = new;
    h.fill();
    `checkd(h.bump_insert(h.q[3000], 10, 1000), 3001);
    `checkd(h.q.size(), N + 1000);
    `checkd(h.q[4000], 3001);
    h.fill();
    `checkd(h.bump_insert(h.q[1000], 3000, 1000), 1001);
    `checkd(h.q[1000], 1001);
    `checkd(h.q[4000], 3000);
    h.fill();
    `checkd(h.bump_erase(h.q[3000], 10), 3001);
    `checkd(h.q[2999], 3001);
    `checkd(h.bump_erase(h.q[2999], 3500), 3002);
    `checkd(h.q[2999], 3002);
    `checkd(h.q.size(), N - 2);
    h.fill();
    `checkd(h.bump_two(h.q[1000], h.q[3000]), 4002);
    `checkd(h.q.size(), N);
    `checkd(h.q[2000], -5);
    // IEEE 1800-2023 7.10.3 keeps both references bound, so the writes would be seen as
    // q[1000] == 1001 and q[3000] == 3001; an insert or delete between two elements passed
    // by reference outdates both, so they are not
    `checkd(h.q[1000], 1000);
    `checkd(h.q[3000], 3000);
  end

  initial begin  // Queue assigned from another queue
    automatic Holder h = new;
    automatic Holder src = new;
    h.fill();
    src.fill();
    `checkd(h.bump_copy(h.q[3000], src.q), 3001);
    `checkd(h.q[3000], 3000);
  end

  initial begin  // Bounded queue that discards the element, or is assigned
    automatic Holder h = new;
    h.fill();
    foreach (h.q[j]) h.qb.push_back(j);
    `checkd(h.bump_bounded(h.qb[$]), N);
    `checkd(h.qb.size(), N);
    `checkd(h.qb[N - 1], -9);
    `checkd(h.bump_bounded_copy(h.qb[3000]), -3000);
    `checkd(h.qb[3000], 3000);
    h.qb.delete();
    foreach (h.q[j]) h.qb.push_back(j);
    `checkd(h.bump_bounded_two(h.qb[0], h.qb[$]), N + 1);
    `checkd(h.qb.size(), N);
    `checkd(h.qb[1], kept_bound() ? 1 : 0);
    `checkd(h.qb[N - 1], N - 2);
  end

  initial begin  // A queue used as a FIFO while its head is passed by reference
    automatic Holder h = new;
    automatic int value;
    h.fill();
    // Each call removes the element passed by reference and pushes at the other end, so the
    // reference to the remaining element stays bound in every call, which keeps the queue from
    // being copied
    for (int j = 0; j < N; ++j) begin
      value = h.q[2001];
      h.bump_fifo(h.q[0], h.q[2001], 0);
      `checkd(h.q[2000], kept_bound() ? value + 1 : value);
      `checkd(h.q[N - 1], -1);
    end
    for (int j = 0; j < N; ++j) begin
      value = h.q[1999];
      h.bump_fifo(h.q[$], h.q[1999], 1);
      `checkd(h.q[2000], kept_bound() ? value + 1 : value);
      `checkd(h.q[0], -1);
    end
    `checkd(h.q.size(), N);
  end

  initial begin  // A push reusing the place of a removed element passed by reference
    automatic Holder h = new;
    h.q = '{10, 20, 30};
    h.bump_reuse_front(h.q[0], h.q[2]);
    `checkd(h.q.size(), 3);
    `checkd(h.q[0], 99);
    // IEEE 1800-2023 7.10.3 keeps the reference to the remaining element bound, so the write
    // would be seen as q[2] == 42; a push constructing where an element passed by reference
    // was removed, in storage holding remaining elements, outdates every reference into the
    // queue, so it is not
    `checkd(h.q[2], 30);
    h.q = '{10, 20, 30};
    h.bump_reuse_back(h.q[2], h.q[0]);
    `checkd(h.q[2], 99);
    `checkd(h.q[0], 10);  // As above, IEEE 1800-2023 7.10.3 would give 42
    h.qb3 = '{0, 1, 2, 3};
    h.bump_reuse_bound(h.qb3[0], h.qb3[3]);
    `checkd(h.qb3.size(), 4);
    `checkd(h.qb3[3], 5);
    `checkd(h.qb3[0], 0);  // As above, IEEE 1800-2023 7.10.3 would give 42
  end

  initial begin  // Elements selected within container elements
    automatic Holder h = new;
    automatic int row[4] = '{1, 2, 3, 4};
    automatic pair_t p = '{5, 70'h3_0000_0000_0000_0006};
    repeat (N) h.qr.push_back(row);
    repeat (N) h.qs.push_back(p);
    h.da = new[N];
    `checkd(h.bump_sub(h.qr[0][1], h.qs[$].a, h.da[3000][2]), 10);
    `checkd(h.qr.size(), N - 1);
    `checkd(h.qs.size(), 1);
    `checkd(h.qs[0].a, 6);
    `checkd(h.da.size(), 0);
    `checkd(h.bump_sub_kept(h.qr[5][3], h.qs[0].w), 5);
    `checkd(h.qr[4][3], 5);
    `checkd(h.qs.size(), 0);
    h.da = new[N];
    h.da[3000][1] = 2;
    fork
      h.bump_sub_later(h.da[3000][1]);
      h.da.delete();
    join
  end

  initial begin  // Dynamic array assigned from another
    automatic Holder h = new;
    h.d = new[N];
    h.d2 = new[N];
    foreach (h.d[j]) h.d[j] = j;
    `checkd(h.bump_dcopy(h.d[3000]), 3001);
    `checkd(h.d[3000], 0);
  end

  initial begin  // Dynamic array resized by the callee
    automatic Holder h = new;
    h.d = new[N];
    foreach (h.d[j]) h.d[j] = j;
    `checkd(h.bump_new(h.d[3000]), 3001);
    `checkd(h.d.size(), 2 * N);
    `checkd(h.d[3000], 0);
    foreach (h.d[j]) h.d[j] = j;
    `checkd(h.bump_shrink(h.d[6000]), 6001);
    `checkd(h.d.size(), N);
    `checkd(h.d[N - 1], N - 1);
  end

  initial begin  // Queue of queues deleted by the callee
    automatic Holder h = new;
    h.fill();
    h.qq = '{h.q, h.q};
    `checkd(h.bump_outer(h.qq[1][3000]), 3001);
    `checkd(h.qq.size(), 0);
    h.qq = '{h.q, h.q, h.q, h.q};
    // Inner queues moved within the outer queue
    `checkd(h.bump_shift(h.qq[2][3000], 2), 3001);
    `checkd(h.qq.size(), 0);
    h.qq = '{h.q, h.q, h.q, h.q};
    `checkd(h.bump_shift(h.qq[3][3000], 2), 3001);
    `checkd(h.qq.size(), 0);
  end

  initial begin  // Removing a pinned element leaves the other references bound
    automatic Holder h = new;
    h.fill();
    `checkd(h.bump_pop_other(h.q[0], h.q[3000]), 1);
    `checkd(h.q[0], 1);
    `checkd(h.q[2999], kept_bound() ? 3001 : 3000);
    `checkd(h.q.size(), N - 1);
  end

  initial begin  // Pinned elements popped, then the queue drained, refilled or assigned
    automatic Holder h = new;
    h.fill();
    `checkd(h.bump_drain(h.q[0]), 1);
    `checkd(h.q.size(), 2);
    `checkd(h.q[0], -1);
    `checkd(h.q[1], N - 1);
    h.fill();
    `checkd(h.bump_pop_two(h.q[0], h.q[1]), 3);
    `checkd(h.q.size(), 0);
    h.q.push_back(4);
    `checkd(h.bump_last(h.q[0]), 5);
    `checkd(h.q.size(), 2);
    `checkd(h.q[0], 9);
    `checkd(h.q[1], 8);
    h.fill();
    `checkd(h.bump_pop_assign(h.q[0]), 1);
    `checkd(h.q.size(), 3);
    `checkd(h.q[0], 5);
  end

  initial begin  // Pinned element deleted by index, or popped, with other elements pinned
    automatic Holder h = new;
    h.fill();
    `checkd(h.bump_erase_other(h.q[0], h.q[3000], 0), 1);
    `checkd(h.q[2999], kept_bound() ? 3001 : 3000);
    h.fill();
    `checkd(h.bump_erase_other(h.q[$], h.q[3000], N - 1), N);
    `checkd(h.q[3000], kept_bound() ? 3001 : 3000);
    `checkd(h.q.size(), N - 1);
    h.fill();
    `checkd(h.bump_clear_outer(h.q[0]), 1);
    `checkd(h.q.size(), 0);
    h.fill();
    `checkd(h.bump_pop_insert(h.q[0], h.q[3000], 0), 1);
    `checkd(h.q[0], -5);
    `checkd(h.q.size(), N);
  end

  initial begin  // Queue elements of a queue of queues
    automatic Holder h = new;
    h.fill();
    h.qq = '{h.q, h.q};
    `checkd(h.bump_inner_q(h.qq[0], 1), N + 5);
    h.qq = '{h.q, h.q};
    `checkd(h.bump_inner_q(h.qq[1], 0), N + 5);
  end

  initial begin  // Class handle elements
    automatic Holder h = new;
    automatic Item it = new;
    it.v = 6;
    for (int j = 0; j < N; ++j) h.iq.push_back(it);
    h.bump_item(h.iq[0]);
    `checkd(it.v, 7);
    `checkd(h.iq.size(), 0);
  end

  initial begin  // Queue deleted and refilled while the callee is suspended
    automatic Holder h = new;
    h.fill();
    fork
      h.bump_later(h.q[3000]);
      h.fill();
    join
    `checkd(h.unchanged(), 1);
  end


  int qdel[$];
  int qkept[$];

  task automatic func(ref int vrefed);
`ifdef TEST_NOINLINE
    // verilator no_inline_task
`endif
    `checkd(vrefed, 2);
    #100;
    vrefed = 10;
    #10;
    `checkd(vrefed, 10);
  endtask

  initial begin
    qkept.push_back(1);
    qkept.push_back(2);
    qkept.push_back(3);
    qdel = qkept;
    $display("qkept=%p  qdel=%p", qkept, qdel);
    `checkd(qkept[0], 1);
    `checkd(qkept[1], 2);
    `checkd(qkept[2], 3);

    func(qdel[1]);
    func(qkept[1]);

    $display("qkept=%p  qdel=%p", qkept, qdel);
    `checkd(qdel.size, 0);
    `checkd(qkept[0], 1);
    `checkd(qkept[1], 10);
    `checkd(qkept[2], 3);
  end

  initial begin
    #50;
    `checkd(qdel[1], 2);
    `checkd(qkept[1], 2);
    qdel.delete();
    #100;

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
