// DESCRIPTION: Verilator: Constant-function packed select bounds and alignment
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  function automatic logic [3:0] put(input int i);
    logic [3:0] v = 4'b1001;
    v[i] = 1'b1;
    return v;
  endfunction

  function automatic logic get_ascending(input int i);
    // verilator lint_off ASCRANGE
    logic [0:7] a = 8'h5a;
    // verilator lint_on ASCRANGE
    return a[i];
  endfunction

  function automatic bit [3:0] get_packed(input bit [30:0] i);
    bit [1:0][3:0] p = 8'h37;
    // Intentional authored index width boundary.
    // verilator lint_off WIDTHTRUNC
    return p[i+:1];
    // verilator lint_on WIDTHTRUNC
  endfunction

  function automatic bit [7:0] put_nested(input longint i, input int j);
    bit [1:0][3:0] p = 8'h37;
    // Intentional authored index width boundary.
    // verilator lint_off WIDTHTRUNC
    p[i][j] = 1'b0;
    // verilator lint_on WIDTHTRUNC
    return p;
  endfunction

  function automatic bit get_negative(input int i);
    bit [-3:-6] v = 4'b0001;
    return v[i-:1];
  endfunction

  // Constant positions outside the storage are not wrapped into a valid element
  function automatic logic [3:0] put_constant_outside();
    logic [3:0] v = 4'b1001;
    // verilator lint_off SELRANGE
    v[4] = 1'b1;
    v[-1] = 1'b0;
    // verilator lint_off WIDTHTRUNC
    v[64'h1_0000_0000] = 1'b0;
    // verilator lint_on WIDTHTRUNC
    // verilator lint_on SELRANGE
    return v;
  endfunction

  function automatic bit [7:0] put_packed_outside();
    bit [1:0][3:0] p = 8'h37;
    // verilator lint_off SELRANGE
    p[2] = 4'h0;
    p[-1] = 4'h0;
    // verilator lint_on SELRANGE
    return p;
  endfunction

  localparam logic [3:0] VECTOR = 4'b1001;
  localparam bit [1:0][3:0] PACKED = 8'h37;
  localparam bit [8:5] OFFSET = 4'b0110;
  // verilator lint_off SELRANGE
  // verilator lint_off WIDTHTRUNC
  localparam bit CONSTANT = VECTOR[4] === 1'bx && VECTOR[-1] === 1'bx
                            && VECTOR[64'h1_0000_0000] === 1'bx && VECTOR[3] === 1'b1
                            && PACKED[2] == 4'h0 && PACKED[1] == 4'h3
                            && OFFSET[4] == 1'b0 && OFFSET[9] == 1'b0 && OFFSET[6] == 1'b1
                            && put_constant_outside() == 4'b1001
                            && put_packed_outside() == 8'h37;
  // verilator lint_on WIDTHTRUNC
  // verilator lint_on SELRANGE

  // Compare the values at elaboration time, before runtime X handling.
  localparam bit VALID = put(2) == 4'b1101 && get_ascending(1) == 1'b1 && get_packed(1) == 4'h3
                         && put_nested(0, 1) == 8'h35 && get_negative(-6) == 1'b1;

  // A narrow signed position keeps its sign; bits beyond the storage are unknown
  // verilator lint_off WIDTH
  // verilator lint_off SELRANGE
  localparam logic [7:0] EIGHT = 8'b0001_0001;
  localparam logic [1:0] NEGATIVE_PART = EIGHT[2'sb11+:2];
  localparam logic [3:0] FOUR = 4'b1000;
  localparam logic [1:0] TOP_PART = FOUR[3+:2];
  localparam logic [299:0] WIDE = 300'b1 << 240;
  localparam logic WIDE_NEGATIVE = WIDE[8'shF0];
  // verilator lint_on SELRANGE
  // verilator lint_on WIDTH

  // A constant function index is evaluated before lowering
  function automatic logic [63:0] far_index();
    return 64'h1_0000_0000;
  endfunction
  // verilator lint_off WIDTH
  // verilator lint_off SELRANGE
  localparam logic [3:0] FAR_ELEMENT = PACKED[far_index()];
  localparam logic [3:0] FAR_COUNTED = PACKED[far_index()+:(1+0)];
  // verilator lint_on SELRANGE
  // verilator lint_on WIDTH

  // A partly outside write in a constant function changes only the bits within the storage
  function automatic logic [7:0] put_partial();
    logic [7:0] v = 8'h00;
    // verilator lint_off SELRANGE
    v[0-:2] = 2'b10;
    v[7+:2] = 2'b01;
    // verilator lint_on SELRANGE
    return v;
  endfunction
  localparam logic [7:0] PARTIAL_WRITE = put_partial();

  // Writes to an element of an unpacked array evaluate the element address once, and a write
  // partly outside its element changes only the bits within it
  function automatic bit [31:0] put_rows();
    logic [3:0] rows[2] = '{4'h7, 4'ha};
    int n = 0;
    // verilator lint_off SELRANGE
    rows[n++][9] = 1'b1;
    rows[n++][-1+:2] = 2'b11;
    // verilator lint_on SELRANGE
    return {8'(n), 16'h0, rows[0], rows[1]};
  endfunction
  localparam bit [31:0] ROWS_WRITE = put_rows();

  // A generate condition sees the select's unknown value, not a wrapped bit
  // verilator lint_off WIDTH
  // verilator lint_off SELRANGE
  if (WIDE[8'shF0] !== 1'bx) begin : g_unknown_bad
    initial $fatal(1, "generate condition does not see an unknown select");
  end
  // verilator lint_on SELRANGE
  // verilator lint_on WIDTH

  // An untyped parameter with an unsized value has a 32-bit range (IEEE 1800-2023 6.20.2)
  localparam IMPLICIT = 5;
  localparam IMPLICIT_MASK = 'h1f;
  localparam bit IMPLICIT_RANGE = IMPLICIT[4] === 1'b0 && IMPLICIT[4:3] === 2'b00
                                  && IMPLICIT[31] === 1'b0 && IMPLICIT_MASK[7] === 1'b0;
  if (IMPLICIT_MASK[7] !== 1'b0) begin : g_implicit_bad
    initial $fatal(1, "generate condition sees an unknown bit");
  end

  initial begin
    `checkh(VALID, 1'b1);
    `checkh(CONSTANT, 1'b1);
    `checkh(IMPLICIT_RANGE, 1'b1);
    `checkh(NEGATIVE_PART, 2'b1x);
    `checkh(TOP_PART, 2'bx1);
    `checkh(WIDE_NEGATIVE, 1'bx);
    `checkh(FAR_ELEMENT, 4'h0);  // 2-state, rather than element 0
    `checkh(FAR_COUNTED, 4'h0);  // 2-state, rather than element 0
    `checkh(PARTIAL_WRITE, 8'h81);
    `checkh(ROWS_WRITE, 32'h0200_007b);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
