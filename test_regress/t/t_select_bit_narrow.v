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
      // Test: constant positions out of range, including an unsigned one with bit 31 set
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
