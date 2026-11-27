// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************

// Pins of queue elements passed by reference, driven directly: a pinned element continues to
// exist when removed or when its queue is replaced, as an outdated reference, and references to
// elements that remain stay bound (IEEE 1800-2023 7.10.3, 13.5.2)

#include <verilated.h>
#include VM_PREFIX_INCLUDE

#include <vector>

static int errors = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            VL_PRINTF("%%Error: %s:%d: check failed: %s\n", __FILE__, __LINE__, #cond); \
            ++errors; \
        } \
    } while (0)

using Queue = VlQueue<IData>;

static void fill(Queue& q, int n) {
    q.clear();
    for (int i = 0; i < n; ++i) q.push_back(i);
}

int main() {
    VM_PREFIX* topp = new VM_PREFIX;
    topp->eval();

    {  // Pushes and pops of other elements keep the reference bound
        Queue q;
        fill(q, 100);
        auto&& pin = q.atWriteRef(50);
        for (int i = 0; i < 1000; ++i) q.push_front(-1);
        for (int i = 0; i < 1000; ++i) q.push_back(-2);
        for (int i = 0; i < 1000; ++i) q.pop_front();
        q.pop_back();
        pin.elem() = 500;
        CHECK(q.at(50) == 500);
        q.resize(60);
        q.resize(70);
        static_cast<IData&>(pin) = 501;
        CHECK(q.at(50) == 501);
    }
    {  // A removed element is outdated, with all references to the queue
        Queue q;
        fill(q, 10);
        auto&& front = q.atWriteRef(0);
        auto&& other = q.atWriteAppendRef(5);
        CHECK(q.pop_front() == 0);
        front.elem() = 100;
        other.elem() = 105;
        CHECK(front.elem() == 100);
        CHECK(q.size() == 9);
        CHECK(q.at(0) == 1);
        CHECK(q.at(4) == 5);
        // The queue no longer has pins
        q.push_back(10);
        CHECK(q.pop_back() == 10);
    }
    {  // Erase and insert shift the side holding no pinned element
        Queue q;
        fill(q, 10);
        auto&& pin = q.atWriteRef(5);
        q.erase(2);
        q.insert(1, 99);
        q.erase(8);
        q.insert(8, 98);
        pin.elem() = 55;
        CHECK(q.at(5) == 55);
        CHECK(q.at(1) == 99);
        CHECK(q.at(8) == 98);
        // An erase of the pinned element, or between pinned elements, outdates them
        auto&& back = q.atWriteAppendBackRef(0);
        q.insert(7, 97);
        back.elem() = 1000;
        pin.elem() = 1001;
        CHECK(q.at(5) == 55);
        CHECK(q.at(7) == 97);
        auto&& pin2 = q.atWriteRef(2);
        auto&& pin3 = q.atWriteRef(6);
        q.erase(4);
        pin2.elem() = 2000;
        pin3.elem() = 3000;
        CHECK(q.at(2) != 2000);
        auto&& pin4 = q.atWriteRef(3);
        q.erase(3);
        pin4.elem() = 4000;
        CHECK(q.at(3) != 4000);
    }
    {  // Elements removed by shrinking or the bound are outdated
        Queue q;
        fill(q, 10);
        auto&& pin = q.atWriteRef(8);
        q.resize(5);
        pin.elem() = 88;
        CHECK(q.size() == 5);
        VlQueue<IData, 4> b;
        b.push_back(0);
        b.push_back(1);
        b.push_back(2);
        b.push_back(3);
        auto&& last = b.atWriteRef(3);
        b.insert(0, 9);
        last.elem() = 33;
        CHECK(b.size() == 4);
        CHECK(b.at(3) == 2);
    }
    {  // Replacing the queue outdates its references
        Queue q;
        Queue other;
        fill(other, 3);
        fill(q, 3);
        auto&& a = q.atWriteRef(0);
        q = other;
        a.elem() = 10;
        CHECK(q.at(0) == 0);
        auto&& b = q.atWriteRef(1);
        q.renew_copy(4, q);
        b.elem() = 11;
        CHECK(q.size() == 4);
        CHECK(q.at(1) == 1);
        auto&& c = q.atWriteRef(1);
        q.renew(2);
        c.elem() = 12;
        CHECK(q.at(1) == 0);
        auto&& d = q.atWriteRef(0);
        const std::vector<IData> values{7, 8};
        q.assign(values.begin(), values.end());
        d.elem() = 13;
        CHECK(q.at(0) == 7);
        auto&& e = q.atWriteRef(0);
        VlQueue<IData, 5> bounded;
        bounded.push_back(4);
        q = bounded;
        e.elem() = 14;
        CHECK(q.at(0) == 4);
        auto&& f = q.atWriteRef(0);
        Queue moved{std::move(q)};
        f.elem() = 15;
        CHECK(moved.at(0) == 4);
        auto&& g = moved.atWriteRef(0);
        moved = std::move(other);
        g.elem() = 16;
        CHECK(moved.at(0) == 0);
        Queue copy{moved};
        CHECK(copy.size() == 3);
    }
    {  // A queue destroyed while its element is passed by reference
        Queue* const qp = new Queue;
        fill(*qp, 3);
        auto&& pin = qp->atWriteRef(2);
        delete qp;
        pin.elem() = 20;
        CHECK(pin.elem() == 20);
    }
    {  // Once its references are released, the queue continues without pins
        Queue q;
        fill(q, 3);
        {
            auto&& pin = q.atWriteRef(1);
            pin.elem() = 11;
        }
        q.insert(1, 9);
        CHECK(q.at(1) == 9);
        CHECK(q.at(2) == 11);
    }
    {  // Many references at once, and several to one element
        Queue q;
        fill(q, 1000);
        std::vector<VlRefPin<IData>*> pins;
        for (int i = 0; i < 1000; ++i) pins.push_back(new VlRefPin<IData>(q.atWriteRef(i)));
        auto&& again = q.atWriteRef(999);
        q.pop_back();
        again.elem() = 9999;
        CHECK(pins[999]->elem() == 9999);
        CHECK(pins[0]->elem() == 0);
        for (VlRefPin<IData>* const pinp : pins) delete pinp;
    }

    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    topp->final();
    VL_DO_DANGLING(delete topp, topp);
    return errors ? 10 : 0;
}
