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

// A queue element passed by reference and popped from an end, when it is the last element of
// its storage node at that end: the node stays allocated for it, a following push at that end
// constructs in fresh storage, and a reference to an element that remains stays bound
// (IEEE 1800-2023 7.10.3, 13.5.2)

#include <verilated.h>
#include VM_PREFIX_INCLUDE

#include <cstdio>
#include <vector>

static int errors = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            VL_PRINTF("%%Error: %s:%d: check failed: %s\n", __FILE__, __LINE__, #cond); \
            ++errors; \
        } \
    } while (0)

int main() {
    VM_PREFIX* topp = new VM_PREFIX;
    topp->eval();

    // References to the remaining elements stay bound where the library allows
    const bool bound = VL_REF_SLOTS;
    {
        VlQueue<IData> q;
        for (int i = 0; i < 3000; ++i) q.push_back(i);
        // Pop until the front element is the last of its node
        while (q.size() > 100 && &q.atWriteAppend(1) == &q.atWriteAppend(0) + 1) q.pop_front();
        const IData front = q.at(0);
        const IData kept = q.at(50);
        {
            const VlRefPin<IData> removedPin = q.atWriteAppendRef(0);
            const VlRefPin<IData> survivorPin = q.atWriteAppendRef(50);
            IData& removed = removedPin;
            IData& survivor = survivorPin;
            CHECK(q.pop_front() == front);
            q.push_front(99);
            CHECK(&q.atWriteAppend(0) != &removed);
            // Then the back grows into new nodes
            for (int i = 0; i < 3000; ++i) q.push_back(i);
            removed = 0xdeadbeefU;
            survivor = 42;
            CHECK(removed == 0xdeadbeefU);
            CHECK(q.at(0) == 99);
            CHECK(q.at(50) == (bound ? 42 : kept));
        }
        CHECK(q.at(0) == 99);
        CHECK(q.at(50) == (bound ? 42 : kept));
        for (int i = 0; i < q.size(); ++i) CHECK(i == 0 || q.at(i) != 0xdeadbeefU);
    }
    {
        // At the back: the back element is the first of its node, which std::deque keeps
        // beyond the last element; the other end grows, then the back
        VlQueue<IData> q;
        for (int i = 0; i < 3000; ++i) q.push_back(i);
        while (q.size() > 100
               && &q.atWriteAppend(q.size() - 2) == &q.atWriteAppend(q.size() - 1) - 1) {
            q.pop_back();
        }
        const IData kept = q.at(q.size() - 51);
        {
            const VlRefPin<IData> removedPin = q.atWriteAppendRef(q.size() - 1);
            const VlRefPin<IData> survivorPin = q.atWriteAppendRef(q.size() - 51);
            IData& removed = removedPin;
            IData& survivor = survivorPin;
            q.pop_back();
            for (int i = 0; i < 3000; ++i) q.push_front(i);
            survivor = 42;
            CHECK(q.at(q.size() - 50) == (bound ? 42 : kept));
            q.push_back(99);
            CHECK(&q.atWriteAppend(q.size() - 1) != &removed);
            removed = 0xdeadbeefU;
            CHECK(q.at(q.size() - 1) == 99);
        }
        for (int i = 0; i < q.size(); ++i) CHECK(q.at(i) != 0xdeadbeefU);
    }

    // Many references: the pins of each element are indexed, also several to one element
    {
        VlQueue<IData> q;
        for (int i = 0; i < 100; ++i) q.push_back(i);
        std::vector<VlRefPin<IData>*> pins;
        for (int i = 0; i < 12; ++i) pins.push_back(new VlRefPin<IData>(q.atWriteAppendRef(i)));
        for (int i = 0; i < 3; ++i) pins.push_back(new VlRefPin<IData>(q.atWriteAppendRef(0)));
        // Release a pin between others of its element, then the newest of them
        VL_DO_DANGLING(delete pins[13], pins[13]);
        pins[13] = nullptr;
        VL_DO_DANGLING(delete pins[14], pins[14]);
        pins[14] = nullptr;
        // Popping an element outdates only its pins
        CHECK(q.pop_front() == 0);
        pins[0]->elem() = 1000;
        pins[1]->elem() = 1001;
        CHECK(pins[12]->elem() == 1000);
        CHECK(q.at(0) == 1001);
        for (VlRefPin<IData>* const pinp : pins) delete pinp;
    }

    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    topp->final();
    VL_DO_DANGLING(delete topp, topp);
    return errors ? 10 : 0;
}
