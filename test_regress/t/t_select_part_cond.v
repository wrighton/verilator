// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Members of elements of packed arrays of structures, at element indices in and out of range,
// read through elements of an outer dimension
module t;
  localparam realtime STEP = 1;
  localparam int A = 3;
  localparam int N = 69;
  typedef struct packed {
    bit [72:0] data;
    bit [12:0] len;
  } pkt_t;
  typedef struct packed {
    bit [9:0] data;
    bit [12:0] len;
  } npkt_t;

  // Each element of the outer dimension is wide
  bit [N-1:0][85:0] q;
  pkt_t [A-1:0][N-1:0] head;
  bit [A-1:0][N-1:0][13:0] lens;
  always_comb begin
    for (int i = 0; i < A; i++) begin
      for (int j = 0; j < N; j++) begin
        head[i][j] = q[j];
        lens[i][j] = head[i][j].len + 14'(i);
      end
    end
  end

  // Each element of the outer dimension is narrow
  npkt_t [A-1:0][1:0] nhead;
  always_comb begin
    for (int i = 0; i < A; i++) begin
      for (int j = 0; j < 2; j++) nhead[i][j] = 23'(q[j] >> i);
    end
  end

  initial begin
    for (int c = 0; c < 64; c++) begin
      bit [6:0] k;
      bit [1:0] nk;
      for (int j = 0; j < N; j++) q[j] = {32'(c * 7 + j), 54'(j * 13 + c * 5)};
      k = 7'(c * 37);
      nk = 2'(c);
      #STEP;
      for (int i = 0; i < A; i++) begin
        for (int j = 0; j < N; j++) `checkh(lens[i][j], 14'(q[j][12:0]) + 14'(i));
        // Out of range, the bits of a 2-state element read as zero
        `checkh(head[i][k].len, int'(k) < N ? q[k][12:0] : 13'h0);
        `checkh(nhead[i][nk].len, int'(nk) < 2 ? 13'(q[nk] >> i) : 13'h0);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // A position given by an impure function at each evaluation reads where its last evaluation
  // says, out of range here
  bit [2:0][15:0] fdata;
  int unsigned fcalls;
  function automatic int unsigned fidx();
    ++fcalls;
    return fcalls % 2 == 1 ? 0 : 16;
  endfunction
  initial begin
    bit fy;
    fdata = '0;
    fdata[2][0] = 1'b1;
    fcalls = 0;
    fy = fdata[1][15 >= fidx() ? fidx() : 20];
    `checkh(fcalls, 2);
    `checkh(fy, 1'b0);
  end

  // Also where an evaluation within the position changes what its condition checked: a
  // function in an arm, a function in the condition, or an increment
  int unsigned six;
  function automatic bit sbump();
    six = 16;
    return 1'b1;
  endfunction
  function automatic int unsigned snext();
    six = 16;
    return 0;
  endfunction
  initial begin
    bit sy;
    #2;
    six = 0;
    sy = fdata[1][15 >= six ? (sbump() ? six : 0) : 20];
    `checkh(six, 16);
    `checkh(sy, 1'b0);
    six = 0;
    sy = fdata[1][15 >= snext() ? six : 20];
    `checkh(sy, 1'b0);
    six = 15;
    sy = fdata[1][15 >= six++ ? six : 20];
    `checkh(six, 16);
    `checkh(sy, 1'b0);
  end
endmodule
