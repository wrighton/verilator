// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // Positions known only at run time, all outside the vectors below
  int pos[] = '{9, 10, 16, 1000, 65537, -1};

  // Constant functions writing bits out of range, alone or with bits in range
  function automatic bit [7:0] set_pair(int k);
    bit [15:8] v;
    v = '0;
    v[k+:2] = 2'b11;
    return v;
  endfunction
  function automatic bit [7:0] set_negative(int k);
    bit [7:0] v;
    v = '0;
    v[k] = 1'b1;
    return v;
  endfunction
  function automatic bit [7:0] set_unsigned(int unsigned k);
    bit [7:0] v;
    v = '0;
    v[k] = 1'b1;
    return v;
  endfunction
  localparam bit [7:0] SET_BELOW = set_pair(-1);
  localparam bit [7:0] SET_LOW = set_pair(7);
  localparam bit [7:0] SET_TOP = set_pair(15);
  // verilator lint_off WIDTHTRUNC
  function automatic bit get_bit(longint k);
    bit [7:0] v;
    v = '1;
    return v[k];
  endfunction
  // verilator lint_on WIDTHTRUNC
  localparam bit GET_NEGATIVE = get_bit(-1);
  localparam bit GET_FAR = get_bit(64'h1_0000_0000);
  localparam bit [7:0] SET_NEGATIVE = set_negative(-1);
  localparam bit [7:0] SET_HUGE = set_unsigned(32'h8000_0000);

  // Positions with nested guarded selects, evaluated once, outside procedural code
  bit [23:-8] nest_v;
  int nest_k;
  wire [3:0] nest_y = nest_v[nest_v[nest_v[nest_v[nest_k+:5]+:5]+:5]+:4];
  int nest_events;
  always @(nest_v[nest_v[nest_v[nest_k+:5]+:5]+:5]) ++nest_events;

  int calls;
  function automatic bit [1:0] pick();
    ++calls;
    return 2'd2;
  endfunction

  function automatic int set_one(output bit b);
    b = 1'b1;
    return 7;
  endfunction

  logic [7:0] forced;
  logic [7:0] driver = 8'h00;
  wire [7:0] driven = driver;

  initial begin
    foreach (pos[n]) void'($value$plusargs($sformatf("pos%0d=%%d", n), pos[n]));

    begin
      // Test: bit and part-select writes out of range are ignored, reads give zero
      bit [7:0] v;
      foreach (pos[n]) begin
        v = 8'h5a;
        v[pos[n]] = 1'b1;
        `checkh(v, 8'h5a);
        v[pos[n]+:2] = 2'b11;
        `checkh(v, 8'h5a);
        `checkh(v[pos[n]], 1'b0);
      end
    end

    begin
      // Test: non-zero low bound and ascending range
      bit [15:8] hi;
      // verilator lint_off ASCRANGE
      bit [0:7] asc;
      // verilator lint_on ASCRANGE
      foreach (pos[n]) begin
        if (pos[n] >= 8 && pos[n] <= 15) continue;
        hi = 8'h5a;
        asc = 8'h5a;
        hi[pos[n]] = 1'b1;
        asc[pos[n]] = 1'b1;
        `checkh(hi, 8'h5a);
        `checkh(asc, 8'h5a);
      end
    end

    begin
      // Test: wide vector
      bit [94:0] w;
      int far;
      far = pos[0] + 200;
      w = {95{1'b1}} >> 1;
      w[far] = 1'b0;
      `checkh(w, {95{1'b1}} >> 1);
      `checkh(w[far], 1'b0);
    end

    begin
      // Test: constant positions out of range, including a 32-bit unsigned one with bit 31 set,
      // which is a negative integer
      bit [7:0] v;
      v = 8'h5a;
      // verilator lint_off SELRANGE
      v[9] = 1'b1;
      v[32'h8000_0000] = 1'b1;
      `checkh(v[9], 1'b0);
      `checkh(v[32'h8000_0000], 1'b0);
      // verilator lint_on SELRANGE
      `checkh(v, 8'h5a);
    end

    begin
      // Test: in-range positions still reach their bits
      bit [7:0] v;
      int k;
      k = pos[0] - 6;
      v = 8'h00;
      v[k] = 1'b1;
      v[k+1+:2] = 2'b11;
      `checkh(v, 8'h38);
      `checkh(v[k], 1'b1);
      `checkh(v[pos[1] & 7], 1'b0);
    end

    begin
      // Test: masked positions, including through another array, reach their bit
      bit [7:0] v;
      int fixed_pos[6];
      foreach (fixed_pos[n]) fixed_pos[n] = pos[n];
      foreach (fixed_pos[n]) begin
        v = 8'h00;
        v[pos[n] & 7] = 1'b1;
        `checkh(v[pos[n] & 7], 1'b1);
        v[fixed_pos[n] & 7] = 1'b0;
        `checkh(v[fixed_pos[n] & 7], 1'b0);
      end
    end

    begin
      // Test: positions bounded by their expression reach their bits
      bit [23:0] v;
      bit [2:0] lane;
      bit [4:0] a;
      bit [4:0] b;
      bit choose;
      longint far;
      lane = 3'(pos[0] - 2);
      a = 5'(pos[0] & 3);
      b = 5'(pos[1] & 3);
      choose = pos[0] > pos[1];
      far = longint'(pos[0]) << 40;
      v = '0;
      v[lane*3+:3] = 3'b101;
      v[lane*2+:2] = 2'b11;
      v[(choose ? a : b) + 5'd1] = 1'b1;
      v[int'(a)] = 1'b1;
      // verilator lint_off WIDTHTRUNC
      v[far] = 1'b1;
      // verilator lint_on WIDTHTRUNC
      `checkh(v, 24'ha0c00a);
    end

    begin
      // Test: positions computed from the index do not wrap into the vector, while a 32-bit
      // unsigned index is an integer, so 32'hffff_fffe selects bit -2
      bit [-1:-8] neg;
      bit [1:0][7:0] lanes;
      int unsigned u;
      int unsigned row;
      bit [64:0] wide;
      u = 32'hffff_fff5 + pos[0];
      row = 32'h1fff_fff7 + pos[0];
      wide = 65'h0_ffff_fff7 + 65'(pos[0]);
      neg = 8'h40;
      lanes = 16'h00a5;
      `checkh(neg[int'(u)], 1'b1);
      `checkh(neg[u], 1'b1);
      `checkh(lanes[row], 8'h00);
      `checkh(lanes[wide], 8'h00);
      neg[u] = 1'b0;
      lanes[row] = 8'hff;
      lanes[wide] = 8'hff;
      `checkh(neg, 8'h00);
      `checkh(lanes, 16'h00a5);
    end

    begin
      // Test: literal positions do not wrap into the vector either
      bit [-1:-8] neg;
      bit [1:0][7:0] lanes;
      neg = 8'h40;
      lanes = 16'h00a5;
      `checkh(neg[32'hffff_fffe], 1'b1);
      neg[32'hffff_fffe] = 1'b0;
      `checkh(neg, 8'h00);
      // verilator lint_off SELRANGE
      `checkh(lanes[32'h2000_0000], 8'h00);
      lanes[32'h2000_0000] = 8'hff;
      // verilator lint_on SELRANGE
      `checkh(lanes, 16'h00a5);
      // verilator lint_off SELRANGE
      `checkh(lanes[32'shdfff_ffff], 8'h00);
      `checkh(lanes[2'd2], 8'h00);
      // verilator lint_on SELRANGE
    end

    begin
      // Test: wide literal and fixed slice positions do not wrap into the vector
      bit [1:0][7:0] lanes;
      lanes = 16'(pos[0] * 16'h0a0b + 16'h0081);
      `checkh(lanes[65'h1], 8'h5a);
      `checkh(lanes[1:1], 8'h5a);
      // verilator lint_off SELRANGE
      `checkh(lanes[65'h1_0000_0000], 8'h00);
      `checkh(lanes[32'h2000_0000:32'h2000_0000], 8'h00);
      lanes[65'h1_0000_0000] = 8'hff;
      lanes[32'h2000_0000:32'h2000_0000] = 8'hff;
      // verilator lint_on SELRANGE
      `checkh(lanes, 16'h5ae4);
    end

    begin
      // Test: an index expression wraps at its own width before it is rebased
      bit [7:-8] v;
      bit [15:8] w;
      int unsigned u;
      int unsigned usaved;
      int k;
      int saved;
      v = 16'h0100 << (pos[0] - 9);
      w = 8'(pos[0] - 8);
      u = 32'hffff_fff6 + pos[0];
      usaved = u + 32'd1;
      `checkh(v[usaved], 1'b1);
      `checkh(v[u + 32'd1], 1'b1);
      `checkh(v[u + 32'd2], 1'b0);
      k = 32'sh8000_0000 + pos[0] - 9;
      saved = k + 32'sh8000_0008;
      `checkh(w[saved+:2], 2'b01);
      `checkh(w[(k + 32'sh8000_0008)+:2], 2'b01);
      `checkh(w[(k + 32'sh8000_0008)+:1], 1'b1);
    end

    begin
      // Test: a range at the most negative integer selects by offset from it
      bit [32'sh8000_0007:32'sh8000_0000] v;
      int k;
      v = 8'(pos[0] - 7);
      k = 32'sh8000_0001 + pos[0] - 9;
      `checkh(v[32'sh8000_0001], 1'b1);
      `checkh(v[k], 1'b1);
      `checkh(v[k+:2], 2'b01);
      `checkh(v[32'sh8000_0007], 1'b0);
    end

    begin
      // Test: a literal index wider than 32 bits is its full value
      bit [7:-8] v;
      v = 16'h0100 << (pos[0] - 9);
      // verilator lint_off WIDTH
      `checkh(v[64'shffff_ffff_ffff_fffe+:2], 2'b00);
      `checkh(v[64'shffff_ffff_ffff_ffff+:2], 2'b10);
      `checkh(v[40'shff_ffff_fffa+:2], 2'b00);
      `checkh(v[40'shff_ffff_ffff], 1'b0);
      `checkh(v[40'sh00_0000_0000], 1'b1);
      // verilator lint_off SELRANGE
      `checkh(v[33'h1_0000_0000], 1'b0);
      // verilator lint_on SELRANGE
      // verilator lint_on WIDTH
    end

    begin
      // Test: a bit of a packed array element out of range is out of range, read or written
      bit [1:0][7:0] lanes;
      lanes = 16'h0001 << (pos[0] - 9);
      // verilator lint_off SELRANGE
      `checkh(lanes[32'd536870911][1], 1'b0);
      lanes = '0;
      lanes[32'd536870911][1] = 1'b1;
      // verilator lint_on SELRANGE
      `checkh(lanes, 16'h0000);
    end

    begin
      // Test: a part-select written through an element at a wide index out of range is not
      // written, even where it starts below the element
      bit [1:0][7:0] lanes;
      longint k;
      int j;
      k = 64'sh7fff_ffff + 64'(pos[0]) - 7;
      j = pos[0] - 9;
      lanes = '0;
      lanes[k][j-:2] = 2'b11;
      lanes[-k][j+:2] = 2'b11;
      `checkh(lanes, 16'h0000);
    end

    begin
      // Test: the index of a write to a bit out of range of its element is evaluated
      bit [2:0][2:0] lanes;
      lanes = '0;
      calls = 0;
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      lanes[pick()][-1] = 1'b0;
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
      `checkh(calls, 1);
      `checkh(lanes, 9'h000);
    end

    begin
      // Test: so is one at a variable position
      bit [1:0][7:0] lanes;
      int k;
      int j;
      k = 32'h2000_0000 + pos[0] - 9;
      j = pos[0] - 8;
      lanes = 16'h0001 << (pos[0] - 9);
      `checkh(lanes[k][j], 1'b0);
      lanes = '0;
      lanes[k][j] = 1'b1;
      `checkh(lanes, 16'h0000);
    end

    begin
      // Test: bits of a packed array element above it are out of range, not the next element
      bit [102:96][2:0] lanes;
      int k;
      k = 96 + pos[0] - 9;
      lanes = '1;
      // verilator lint_off SELRANGE
      `checkh(lanes[k][3-:1], 1'b0);
      `checkh(lanes[k][4-:2], 2'b00);
      // verilator lint_on SELRANGE
    end

    begin
      // Test: so is the index of a read or write past the end of its element
      bit [2:0][2:0] lanes;
      lanes = 9'h1c7;
      calls = 0;
      // verilator lint_off SELRANGE
      `checkh(lanes[pick()][3], 1'b0);
      lanes[pick()][3] = 1'b0;
      // verilator lint_on SELRANGE
      `checkh(calls, 2);
      `checkh(lanes, 9'h1c7);
    end

    begin
      // Test: a selection wider than a 2-state vector, wholly below it, reads zeros
      // verilator lint_off ASCRANGE
      bit [0:30] v;
      // verilator lint_on ASCRANGE
      bit [37:0] i;
      v = 31'h209b_8d25;
      i = 38'(pos[5] * 33);
      // verilator lint_off SELRANGE
      `checkh(v[$signed(i)-:64], 64'h0);
      // verilator lint_on SELRANGE
    end

    begin
      // Test: a read out of range of the element a queue method returns still pops it
      bit [7:0] popped[$];
      bit got1;
      bit [3:0] got4;
      int at;
      at = pos[0] - 1;
      repeat (3) popped.push_back(8'h5a);
      // verilator lint_off SELRANGE
      got1 = popped.pop_front()[8];
      `checkh(got1, 1'b0);
      got1 = popped.pop_front()[at];
      `checkh(got1, 1'b0);
      got4 = popped.pop_front()[at+:4];
      `checkh(got4, 4'h0);
      // verilator lint_on SELRANGE
      `checkh(popped.size(), 0);
    end

    begin
      // Test: so does one of a 4-state element narrower than the selection
      logic [2:0] narrow[$];
      logic [3:0] got4;
      narrow.push_back(3'h5);
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      got4 = narrow.pop_front()[6-:4];
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
      `checkh(narrow.size(), 0);
    end

    begin
      // Test: a lane of a packed slice partly below the vector is read
      typedef bit [1:0][3:0] lanes_t;
      lanes_t lanes;
      lanes_t lanes_q[$];
      bit [3:0] got;
      lanes = 8'ha5;
      lanes_q.push_back(8'ha5);
      // verilator lint_off SELRANGE
      got = lanes[0:-1][0];
      `checkh(got, 4'h5);
      got = lanes_q.pop_back()[0:-1][0];
      `checkh(got, 4'h5);
      // verilator lint_on SELRANGE
      `checkh(lanes_q.size(), 0);
    end

    begin
      // Test: a lane outside a packed slice partly below the vector reads zero
      typedef bit [1:0][3:0] lanes_t;
      lanes_t lanes;
      lanes_t lanes_q[$];
      int j;
      bit [3:0] got;
      lanes = 8'ha5;
      lanes_q.push_back(8'ha5);
      lanes_q.push_back(8'ha5);
      j = pos[0] - 8;
      // verilator lint_off SELRANGE
      got = lanes[0:-1][j];
      `checkh(got, 4'h0);
      got = lanes_q.pop_back()[0:-1][j];
      `checkh(got, 4'h0);
      // Test: and one inside it reads its lane
      j = pos[0] - 9;
      got = lanes[0:-1][j];
      `checkh(got, 4'h5);
      got = lanes_q.pop_back()[0:-1][j];
      `checkh(got, 4'h5);
      // verilator lint_on SELRANGE
      `checkh(lanes_q.size(), 0);
    end

    begin
      // Test: an element out of range of an unpacked array of packed elements reads zero
      typedef bit [1:0][3:0] lanes_t;
      typedef lanes_t payload_t[0:2];
      payload_t payload;
      payload_t payload_q[$];
      bit [1:0] at;
      bit [3:0] got;
      payload = '{8'ha5, 8'hb6, 8'hc7};
      payload_q.push_back(payload);
      at = 2'(pos[0] - 6);
      got = payload[at][0];
      `checkh(got, 4'h0);
      got = payload_q.pop_front()[at][0];
      `checkh(got, 4'h0);
      `checkh(payload_q.size(), 0);
    end

    begin
      // Test: a lane of a packed struct member at a wide index folded late is read
      typedef bit [14:0][3:0] lanes_t;
      typedef struct packed {
        bit pad;
        lanes_t f;
      } wrap_t;
      wrap_t w;
      w = '{1'b1, 60'h931_06db_f7c8_9df3};
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      `checkh(w.f[40'((-32'sd1))][3-:1], 1'b0);
      `checkh(w.f[40'((32'sd2))], 4'hd);
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
    end

    begin
      // Test: an element out of range of an unpacked popped value is read, once popped
      typedef bit [7:0] bytes_t[0:2];
      bytes_t bytes_q[$];
      bytes_t bytes;
      int at;
      bit got;
      bytes = '{8'h81, 8'h42, 8'h24};
      bytes_q.push_back(bytes);
      at = pos[0] - 6;
      got = bytes_q.pop_front()[at][0];
      `checkh(got, 1'b0);
      `checkh(bytes_q.size(), 0);
    end

    begin
      // Test: positions with nested guarded selects in a continuous assignment and an event
      // control
      int events;
      nest_v = 32'hacab_1a6b ^ 32'(pos[0] - 9);
      nest_k = pos[0] - 7;
      #1;
      `checkh(nest_y, 4'ha);
      events = nest_events;
      nest_v[16] = ~nest_v[16];
      #1;
      `checkh(nest_events, events + 1);
      `checkh(nest_y, 4'h0);
    end

    begin
      // Test: a constant 4-state part-select extending above the value reads its bits in range
      logic [8:0] v;
      logic [16:0] got;
      v = 9'h109 ^ 9'(pos[0] - 9);
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      got = v[3'sd0+:17];
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
      `checkh(got[8:0], 9'h109);
    end

    begin
      // Test: a part-select of a member lane out of range of a popped 4-state element pops once
      typedef logic [2:1][3:0] lanes_t;
      typedef struct packed {
        bit pad;
        lanes_t f;
      } wrap_t;
      wrap_t q[$][0:2];
      wrap_t a[0:2];
      logic [4:0] got;
      int u;
      foreach (a[k]) a[k] = '{1'b1, 8'h8a};
      q.push_back(a);
      u = pos[0] - 8;
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      got = q.pop_front()[u].f[$signed(3'sd3)][5-:5];
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
      `checkh(q.size(), 0);
    end

    begin
      // Test: an ascending vector at the integer limit, at a position folded far below it
      // verilator lint_off ASCRANGE
      bit [2147483632:2147483647] v;
      // verilator lint_on ASCRANGE
      bit signed [0:0] i;
      v = 16'h3499 ^ 16'(pos[0] - 9);
      i = 1'(pos[0] - 9);
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      `checkh(v[(i<<3)+:7], 7'h0);
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
    end

    begin
      // Test: a lane of a popped value at a random index draws the index once
      typedef bit [3:0][7:0] lanes_t;
      lanes_t q[$];
      int unsigned n;
      int unsigned seed;
      int unsigned draw1;
      int unsigned draw2;
      bit [7:0] got;
      n = pos[0] - 5;
      seed = 123;
      do begin
        ++seed;
        void'($urandom(seed));
        draw1 = $urandom();
        draw2 = $urandom();
      end while (draw1 % n == draw2 % n);
      q.push_back(32'h4433_2211);
      void'($urandom(seed));
      got = q.pop_front()[$urandom() % n];
      `checkh(got, 8'(32'h4433_2211 >> (8 * (draw1 % n))));
      `checkh($urandom(), draw2);
      `checkh(q.size(), 0);
    end

    begin
      // Test: a select far above the value next to one in range reads only the one in range
      bit [15:0] v;
      bit [7:0] got;
      v = 16'h5a3c ^ 16'(pos[0] - 9);
      // verilator lint_off SELRANGE
      got = {v[6:3], v[32'h4000_0000+:4]};
      // verilator lint_on SELRANGE
      `checkh(got, 8'h70);
    end

    begin
      // Test: a write far above the value next to one in range writes only the one in range
      bit [15:0] v;
      bit [3:0] a;
      bit [3:0] b;
      a = 4'hf ^ 4'(pos[0] - 9);
      b = 4'h0 ^ 4'(pos[0] - 9);
      v = 16'h0;
      // verilator lint_off SELRANGE
      v[32'h4000_0000+:4] = a;
      // verilator lint_on SELRANGE
      v[6:3] = b;
      `checkh(v, 16'h0);
    end

    begin
      // Test: a select far above a concatenation reads none of its bits
      bit [7:0] a;
      bit [3:0] b;
      bit [7:0] got;
      a = 8'ha5 ^ 8'(pos[0] - 9);
      b = 4'h3 ^ 4'(pos[0] - 9);
      // verilator lint_off SELRANGE
      got = {a, b}[32'h4000_0000+:8];
      // verilator lint_on SELRANGE
      `checkh(got, 8'h0);
    end

    begin
      // Test: a select above a replication, a negation or an extension reads no bit of it
      bit [7:0] a;
      bit [3:0] n;
      bit got;
      bit [3:0] got4;
      int k;
      a = 8'h01 ^ 8'(pos[0] - 9);
      n = 4'h5 ^ 4'(pos[0] - 9);
      k = pos[0] + 7;
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      got = {2{a}}[16];
      `checkh(got, 1'b0);
      got = {2{a}}[32'h4000_0000];
      `checkh(got, 1'b0);
      got = {2{a}}[k];
      `checkh(got, 1'b0);
      got = {~a}[9];
      `checkh(got, 1'b0);
      got = {~a}[k - 7];
      `checkh(got, 1'b0);
      got = {a ^ 8'hff}[k];
      `checkh(got, 1'b0);
      got = {a | 8'h00}[32'h4000_0000];
      `checkh(got, 1'b0);
      got4 = {16'(n)}[18+:4];
      `checkh(got4, 4'h0);
      got4 = {16'(n)}[32'h4000_0000+:4];
      `checkh(got4, 4'h0);
      a = 8'hc1 ^ 8'(pos[0] - 9);
      got4 = {2{a}}[14+:4];
      `checkh(got4, 4'h3);
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
    end

    begin
      // Test: a lane window of a slice past a popped value reads its lanes in range, popped once
      typedef bit [1:0][3:0] lanes_t;
      lanes_t q[$];
      int j;
      bit [7:0] got8;
      bit [3:0] got4;
      for (int k = 0; k < 4; ++k) q.push_back(8'ha5);
      j = pos[0] - 8;
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      got8 = q.pop_back()[1:-1][j+:2];
      `checkh(got8, 8'h0a);
      got4 = q.pop_back()[1:-1][j];
      `checkh(got4, 4'ha);
      j = pos[0] - 9;
      got8 = q.pop_back()[1:-1][j+:2];
      `checkh(got8, 8'ha5);
      got4 = q.pop_back()[1:-1][j];
      `checkh(got4, 4'h5);
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
      `checkh(q.size(), 0);
    end

    begin
      // Test: a lane window of a slice ending below the top of a packed array reads only the
      // lanes of the slice
      typedef bit [2:0][3:0] lanes_t;
      lanes_t p;
      lanes_t q[$];
      int j;
      bit [7:0] got;
      p = 12'h3a5 ^ 12'(pos[0] - 9);
      for (int k = 0; k < 2; ++k) q.push_back(p);
      j = pos[0] - 8;
      // verilator lint_off SELRANGE
      got = p[1:-1][j+:2];
      `checkh(got, 8'h0a);
      got = q.pop_back()[1:-1][j+:2];
      `checkh(got, 8'h0a);
      j = pos[0] - 9;
      got = p[1:-1][j+:2];
      `checkh(got, 8'ha5);
      got = q.pop_back()[1:-1][j+:2];
      `checkh(got, 8'ha5);
      // verilator lint_on SELRANGE
      `checkh(q.size(), 0);
    end

    begin
      // Test: a bit of a part-select of a packed union at a position computed signed
      union packed {
        logic [31:0][7:0] idx;
        struct packed {
          logic [15:0] z, y, x;
          logic [25:0][7:0] r;
        } nam;
      } g;
      logic got;
      g = 256'h12346789_abcdef12_3456789a_bcdef123_456789ab_cdef1234_56789abc_def12345;
      for (int k = 0; k < 15; ++k) begin
        got = g[255:255-14][k+pos[0]-9];
        `checkh(got, g[241+k]);
      end
    end

    begin
      // Test: lane windows of slices of wide queued packed arrays past their bottom
      typedef bit [3:0][31:0] lanes_t;
      lanes_t q[$];
      int j;
      bit [95:0] got96;
      bit [63:0] got64;
      for (int k = 0; k < 2; ++k) q.push_back(128'h4444_4444_3333_3333_2222_2222_1111_1111);
      j = pos[0] - 9;
      // verilator lint_off SELRANGE
      got96 = q.pop_back()[1:-1][j+:3];
      `checkh(got96, 96'h0000_0000_2222_2222_1111_1111);
      j = pos[0] - 7;
      got64 = q.pop_back()[2:-1][j+:2];
      `checkh(got64, 64'h0000_0000_3333_3333);
      // verilator lint_on SELRANGE
      `checkh(q.size(), 0);
    end

    begin
      // Test: a select of a constant all X draws its random position once
      localparam logic [7:0] X4 = 'x;
      logic got;
      int unsigned n;
      int unsigned seed;
      int unsigned draw1;
      int unsigned draw2;
      n = pos[0] - 1;
      seed = 123;
      do begin
        ++seed;
        void'($urandom(seed));
        draw1 = $urandom();
        draw2 = $urandom();
      end while (draw1 == draw2);
      void'($urandom(seed));
      got = X4[$urandom()%n];
      `checkh($urandom(), draw2);
    end

    begin
      // Test: a negative narrow signed literal selects no bit
      bit [15:0] v;
      logic [15:0] l;
      v = 16'h1234 ^ 16'(pos[0] - 9);
      l = 16'h1234 ^ 16'(pos[0] - 9);
      // verilator lint_off SELRANGE
      `checkh(v[-3'sd1], 1'b0);
      v[-3'sd1] = 1'b1;
      l[-3'sd1] = 1'b1;
      v[-3'sd2+:2] = 2'b11;
      // verilator lint_on SELRANGE
      `checkh(v, 16'h1234);
      `checkh(l, 16'h1234);
    end

    begin
      // Test: a narrow signed literal in range selects its bit
      bit [3:-4] v;
      v = 8'(pos[0] + 25);
      `checkh(v[32'sd1], 1'b1);
      `checkh(v[3'sd1], 1'b1);
      `checkh(v[3'sb100], 1'b0);
      `checkh(v[-3'sd3], 1'b1);
      `checkh(v[2'd3], 1'b0);
    end

    begin
      // Test: signed indices select by value in ascending ranges and part-selects
      // verilator lint_off ASCRANGE
      bit [0:7] asc;
      // verilator lint_on ASCRANGE
      bit [7:0] v;
      bit [1:0][7:0] lanes;
      logic signed [3:0] s;
      logic signed [2:0] t;
      int unsigned u;
      asc = 8'h5a;
      v = 8'h5a;
      lanes = 16'h00a5;
      s = 4'(pos[5]);
      `checkh(asc[s], 1'b0);
      asc[s] = 1'b1;
      `checkh(asc, 8'h5a);
      s = 4'(pos[0] - 8);
      `checkh(asc[s], 1'b1);
      t = 3'(pos[5] - 3);
      `checkh(v[t+:2], 2'b00);
      `checkh(v[t-:2], 2'b00);
      v[t+:2] = 2'b11;
      `checkh(v, 8'h5a);
      u = 32'h1fff_fff7 + pos[0];
      `checkh(lanes[u+:1], 8'h00);
      `checkh(v[u-:2], 2'b00);
      t = 3'(pos[5] - 3);
      `checkh(asc[t+:2], 2'b00);
      `checkh(lanes[t+:1], 8'h00);
      t = 3'(pos[0] - 8);
      `checkh(asc[t+:2], 2'b10);
      `checkh(lanes[t+:1], 8'h00);
    end

    begin
      // Test: a negative narrow signed index selects no bit
      bit [7:0] v;
      logic signed [2:0] s;
      s = 3'(pos[5]);
      v = 8'h5a;
      v[s] = 1'b1;
      `checkh(v, 8'h5a);
      `checkh(v[s], 1'b0);
      // A size cast keeps the signedness of its operand (IEEE 1800-2023 6.24.1)
      v[3'(pos[0] - 4)] = 1'b1;
      `checkh(v, 8'h5a);
      `checkh(v[3'(pos[0] - 4)], 1'b0);
    end

    begin
      // Test: 4-state vector writes out of range are ignored
      logic [7:0] v;
      foreach (pos[n]) begin
        v = 8'h5a;
        v[pos[n]] = 1'b1;
        `checkh(v, 8'h5a);
      end
    end

    begin
      // Test: a part-select partly above the vector writes and reads its bits in range
      bit [7:0] v;
      int k;
      k = pos[0] - 2;
      v = 8'h00;
      v[k+:2] = 2'b11;
      `checkh(v, 8'h80);
      `checkh(v[k+:2], 2'b01);
    end

    // Test: constant functions write only bits in range
    `checkh(SET_BELOW, 8'h00);
    `checkh(SET_LOW, 8'h01);
    `checkh(SET_TOP, 8'h80);
    `checkh(SET_NEGATIVE, 8'h00);
    `checkh(SET_HUGE, 8'h00);
    `checkh(GET_NEGATIVE, 1'b0);
    `checkh(GET_FAR, 1'b0);

    // Test: forcing and releasing a bit out of range do nothing
    forced = 8'h5a;
    // verilator lint_off SELRANGE
    force forced[32'shffff_ffff] = 1'b1;
    `checkh(forced, 8'h5a);
    release forced[32'shffff_ffff];
    // verilator lint_on SELRANGE
    `checkh(forced, 8'h5a);

    begin
      // Test: a blocking assignment with an intra-assignment timing control selects its bit
      // when the wait ends, and a nonblocking one when it is scheduled
      bit [7:0] v;
      int k;
      event go;
      v = '0;
      k = pos[0] - 1;
      fork
        v[k] = #2 1'b1;
        #1 k = 1;
      join
      `checkh(v, 8'h02);
      k = 2;
      fork
        v[k] = #2 1'b1;
        #1 k = pos[0];
      join
      `checkh(v, 8'h02);
      k = pos[0];
      fork
        v[k] = @(go) 1'b1;
        begin
          #1 k = 3;
          ->go;
        end
      join
      `checkh(v, 8'h0a);
      k = 4;
      fork
        v[k] <= #2 1'b1;
        #1 k = pos[0];
      join
      #2;
      `checkh(v, 8'h1a);
      k = pos[0];
      fork
        v[k] <= #2 1'b1;
        #1 k = 5;
      join
      #2;
      `checkh(v, 8'h1a);
    end

    begin
      // Test: a select written by the value of such an assignment is selected before the wait,
      // and the target is still written after it
      bit [7:0] v;
      int k;
      int x;
      v = '0;
      k = pos[0];
      x = 0;
      x = #2 set_one(v[k]);
      `checkh(x, 7);
      `checkh(v, 8'h00);
      fork
        x = #2 set_one(v[k]);
        #1 k = 1;
      join
      `checkh(v, 8'h00);
    end

    begin
      // Test: the same for an unpacked array element
      int arr[4];
      int k;
      arr = '{0, 0, 0, 0};
      k = pos[0];
      fork
        arr[k] = #2 7;
        #1 k = 1;
      join
      `checkh(arr[1], 7);
    end

    // Test: releasing a part-select partly above the vector releases its bit in range
    force driven[7] = 1'b1;
    #1;
    `checkh(driven, 8'h80);
    // verilator lint_off SELRANGE
    release driven[7+:2];
    // verilator lint_on SELRANGE
    #1;
    `checkh(driven, 8'h00);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
