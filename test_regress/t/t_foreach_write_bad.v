// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Node;
  bit succ[Node];
  int v;
endclass

typedef struct packed {
  bit [3:0] hi;
  bit [3:0] lo;
} key_t;

module t;
  int a[3];
  int b[2][4];
  int m[string];

  initial begin
    foreach (a[i]) begin
      i = 2;  // Illegal 12.7.3
    end
    foreach (b[i, j]) begin
      j++;  // Illegal 12.7.3
    end
    foreach (a[i]) begin
      foreach (b[k]) begin
        for (int n = 0; n < 2; n++) a[n] = k;  // OK
        i += 1;  // Illegal 12.7.3
      end
    end
    foreach (m[s]) begin
      s = "x";  // Illegal 12.7.3
    end
    begin
      Node pred[Node];
      Node n;
      foreach (pred[p]) begin
        p.succ[n] = 1;  // OK, writes the object p refers to
        p.v = 1;  // OK
      end
    end
    begin
      int km[key_t];
      foreach (km[k]) begin
        k.lo = 1;  // Illegal 12.7.3
        k[0] = 1'b1;  // Illegal 12.7.3
      end
    end
  end
endmodule
