// DESCRIPTION: Verilator: live force RHS functions reading virtual interfaces
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface force_lane;
  logic [6:0] sig;
endinterface

module t;
  typedef logic [6:0] word_t;
  force_lane a ();
  force_lane b ();
  virtual force_lane vh;
  word_t direct, nested, from_handle;
  int calls;

  function automatic word_t mix(word_t d);
    return d ^ 7'h5a;
  endfunction

  function automatic word_t read_handle(virtual force_lane h);
    ++calls;
    return h.sig;
  endfunction

  initial begin
    a.sig = 7'd1;
    b.sig = 7'd1;
    vh = a;
    #1;
    force direct = mix(vh.sig);
    force nested = ~mix(vh.sig);
    force from_handle = read_handle(vh);
    #1;
    if ({direct, nested, from_handle} !== {7'h5b, 7'h24, 7'd1} || calls != 1)
      $fatal(1, "Unexpected value or repeated activation");
    a.sig = 7'd5;
    #1;
    if ({direct, nested} !== {7'h5f, 7'h20} || calls != 1) $fatal(1, "First member update");
    b.sig = 7'd5;
    vh = b;
    #1;
    if ({direct, nested, from_handle} !== {7'h5f, 7'h20, 7'd5} || calls != 2)
      $fatal(1, "Handle change did not trigger with equal member values");
    vh.sig = 7'd17;
    #1;
    if ({direct, nested} !== {7'h4b, 7'h34} || calls != 2) $fatal(1, "Second member update");
    release direct;
    release nested;
    release from_handle;
    vh = null;
    b.sig = 7'd2;
    #1;
    if ({direct, nested, from_handle} !== {7'h4b, 7'h34, 7'd5} || calls != 2)
      $fatal(1, "Released variables did not hold");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
