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

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <unistd.h>

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>

namespace {
static constexpr size_t MAX_BYTES = 7;
size_t s_shortPipeWrites = 0;
size_t s_shortSocketSends = 0;

class ShortTransfers final {
public:
    ~ShortTransfers() {
        if (!s_shortPipeWrites && !s_shortSocketSends) {
            std::fprintf(stderr, "%%Error: No short solver transfer was injected\n");
            std::_Exit(1);
        }
        std::printf("Short solver transfers: %zu (pipe=%zu socket=%zu)\n",
                    s_shortPipeWrites + s_shortSocketSends, s_shortPipeWrites, s_shortSocketSends);
    }
};
ShortTransfers s_shortTransfers;
}  // namespace

// Retain the original pipe path for the unfixed control.
extern "C" ssize_t write(int fd, const void* bufp, size_t count) {
    static constexpr char ANCHOR[] = "(set-option";
    struct stat st;
    if (count > MAX_BYTES && count >= sizeof(ANCHOR) - 1
        && std::memcmp(bufp, ANCHOR, sizeof(ANCHOR) - 1) == 0 && fstat(fd, &st) == 0
        && S_ISFIFO(st.st_mode)) {
        ++s_shortPipeWrites;
    }
    return syscall(SYS_write, fd, bufp, count < MAX_BYTES ? count : MAX_BYTES);
}

// Shorten the actual socket send too, retaining its signal-suppression flags.
extern "C" ssize_t send(int fd, const void* bufp, size_t count, int flags) {
    using SendFn = ssize_t (*)(int, const void*, size_t, int);
    static const SendFn s_fnp = reinterpret_cast<SendFn>(dlsym(RTLD_NEXT, "send"));
    if (!s_fnp) {
        std::fprintf(stderr, "%%Error: Unable to forward send\n");
        std::_Exit(1);
    }
    struct stat st;
    if (count > MAX_BYTES && fstat(fd, &st) == 0 && S_ISSOCK(st.st_mode)) { ++s_shortSocketSends; }
    return s_fnp(fd, bufp, count < MAX_BYTES ? count : MAX_BYTES, flags);
}
