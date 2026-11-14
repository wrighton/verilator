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

// Reuses the solver-fault model with four SIGPIPE states, checking each after main.
// Interposes the actual request socket operations to inject setup/send failures or
// short sends. No production signal-mask or signal-wait seam is required.

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <string>
#include <unistd.h>

#include <sys/socket.h>
#include <sys/stat.h>

namespace {
volatile sig_atomic_t s_handlerCalled = 0;
unsigned s_sendFaults = 0;
unsigned s_shortSends = 0;
unsigned s_setupFaults = 0;
int s_pairFds[2] = {-1, -1};

void handler(int) { s_handlerCalled = 1; }

[[noreturn]] void fail(const char* whatp) {
    std::fprintf(stderr, "%%Error: SIGPIPE socket test: %s\n", whatp);
    std::fflush(stderr);
    std::_Exit(1);
}

const std::string& faultMode() {
    const char* const valuep = std::getenv("SOCKET_FAULT");
    static const std::string s_mode = valuep ? valuep : "";
    return s_mode;
}

using SendFn = ssize_t (*)(int, const void*, size_t, int);
SendFn realSend() {
    static const SendFn s_fnp = reinterpret_cast<SendFn>(dlsym(RTLD_NEXT, "send"));
    if (!s_fnp) fail("Unable to forward send");
    return s_fnp;
}

class EarlySend final {
public:
    EarlySend() {
        const char byte = 0;
        const int savedErrno = errno;
        if (send(-1, &byte, 0, 0) != -1 || errno != EBADF) fail("Early send did not forward");
        errno = savedErrno;
        std::printf("Forwarded send before signal setup\n");
    }
};
const EarlySend s_earlySend;

class SigpipeState final {
    std::string m_state;
    sigset_t m_mask;
    struct sigaction m_action;
    bool m_pending = false;

    bool pending() const {
        sigset_t set;
        if (sigpending(&set) != 0) fail("sigpending failed");
        return sigismember(&set, SIGPIPE) == 1;
    }

public:
    SigpipeState() {
        const char* const statep = std::getenv("SIGPIPE_STATE");
        m_state = statep ? statep : "";
        const bool blocked = m_state == "blocked" || m_state == "pending";
        if (!blocked && m_state != "handler" && m_state != "ignored") fail("Bad signal state");
        sigset_t set;
        sigemptyset(&set);
        sigaddset(&set, SIGUSR1);
        if (pthread_sigmask(SIG_BLOCK, &set, nullptr) != 0) fail("Unrelated block failed");
        sigemptyset(&set);
        sigaddset(&set, SIGPIPE);
        if (pthread_sigmask(blocked ? SIG_BLOCK : SIG_UNBLOCK, &set, nullptr) != 0) {
            fail("SIGPIPE mask setup failed");
        }
        struct sigaction action;
        std::memset(&action, 0, sizeof(action));
        sigemptyset(&action.sa_mask);
        action.sa_handler = m_state == "handler"   ? handler
                            : m_state == "ignored" ? SIG_IGN
                                                   : SIG_DFL;
        if (sigaction(SIGPIPE, &action, nullptr) != 0) fail("Disposition setup failed");
        if (pending()) fail("SIGPIPE pending before setup");
        if (m_state == "pending") {
            if (pthread_kill(pthread_self(), SIGPIPE) != 0) fail("Pending setup failed");
            if (!pending()) fail("Pending signal missing after setup");
        }
        m_pending = pending();
        if (pthread_sigmask(SIG_SETMASK, nullptr, &m_mask) != 0) fail("Mask query failed");
        if (sigaction(SIGPIPE, nullptr, &m_action) != 0) fail("Disposition query failed");
#if defined(MSG_NOSIGNAL)
        std::printf("SIGPIPE suppression: MSG_NOSIGNAL\n");
#elif defined(SO_NOSIGPIPE)
        std::printf("SIGPIPE suppression: SO_NOSIGPIPE\n");
#else
        std::printf("SIGPIPE suppression: unavailable\n");
#endif
    }
    ~SigpipeState() {
        const bool stillPending = pending();
        sigset_t mask;
        struct sigaction action;
        if (pthread_sigmask(SIG_SETMASK, nullptr, &mask) != 0) fail("Final mask query failed");
        if (sigaction(SIGPIPE, nullptr, &action) != 0) fail("Final disposition query failed");
        for (int sig = 1; sig < NSIG; ++sig) {
            if (sigismember(&mask, sig) != sigismember(&m_mask, sig)) fail("Signal mask changed");
            if (sigismember(&action.sa_mask, sig) != sigismember(&m_action.sa_mask, sig)) {
                fail("Handler mask changed");
            }
        }
        if (stillPending != m_pending) fail("Pending signal changed");
        if (action.sa_handler != m_action.sa_handler || action.sa_flags != m_action.sa_flags) {
            fail("Signal disposition changed");
        }
        if (s_handlerCalled) fail("SIGPIPE handler called");
        if (m_pending) {
            // Consume only this fixture's own signal, after checking preservation. This
            // test is single-threaded and never changes SIGPIPE to ignored in this state.
            sigset_t set;
            sigemptyset(&set);
            sigaddset(&set, SIGPIPE);
            int sig;
            if (sigwait(&set, &sig) != 0) fail("Fixture pending cleanup failed");
        }
        const std::string& fault = faultMode();
        if (fault == "short") {
            if (!s_shortSends) fail("No short socket send was injected");
            std::printf("Short socket sends injected: %u\n", s_shortSends);
        } else if (fault == "eio" || fault == "eintr" || fault == "epipe") {
            if (s_sendFaults != 1) fail("Send fault was not injected once");
            std::printf("Socket send fault injected once: %s\n", fault.c_str());
        } else if (fault == "socketpair" || fault == "sockopt") {
            if (s_setupFaults != 1) fail("Setup fault was not injected once");
            if (fault == "sockopt") {
                for (int fd : s_pairFds) {
                    if (fd < 0 || fcntl(fd, F_GETFD) != -1 || errno != EBADF) {
                        fail("Failed socket-option setup leaked an endpoint");
                    }
                }
            }
            std::printf("Socket setup fault injected once: %s\n", fault.c_str());
        } else if (!fault.empty()) {
            fail("Unknown socket fault");
        }
        std::printf("SIGPIPE state kept: %s\n", m_state.c_str());
        std::fflush(stdout);
    }
};
SigpipeState s_sigpipeState;
}  // namespace

extern "C" ssize_t send(int fd, const void* bufp, size_t count, int flags) {
    static constexpr char ANCHOR[] = "(set-option";
    struct stat st;
    const bool socket = fstat(fd, &st) == 0 && S_ISSOCK(st.st_mode);
    const std::string& fault = faultMode();
    if (socket && !s_sendFaults && count >= sizeof(ANCHOR) - 1
        && std::memcmp(bufp, ANCHOR, sizeof(ANCHOR) - 1) == 0) {
        if (fault == "eio" || fault == "eintr" || fault == "epipe") {
            ++s_sendFaults;
            errno = fault == "eio" ? EIO : fault == "eintr" ? EINTR : EPIPE;
            return -1;
        }
    }
    if (socket && fault == "short" && count > 7) {
        ++s_shortSends;
        count = 7;
    }
    return realSend()(fd, bufp, count, flags);
}

extern "C" int socketpair(int domain, int type, int protocol, int fds[2])
#if defined(__GLIBC__)
    noexcept
#endif
{
    if (domain == AF_UNIX && type == SOCK_STREAM && faultMode() == "socketpair"
        && !s_setupFaults) {
        ++s_setupFaults;
        errno = EMFILE;
        return -1;
    }
    using PairFn = int (*)(int, int, int, int*);
    static const PairFn s_fnp = reinterpret_cast<PairFn>(dlsym(RTLD_NEXT, "socketpair"));
    if (!s_fnp) fail("Unable to forward socketpair");
    const int rc = s_fnp(domain, type, protocol, fds);
    if (rc == 0 && domain == AF_UNIX && type == SOCK_STREAM) {
        s_pairFds[0] = fds[0];
        s_pairFds[1] = fds[1];
    }
    return rc;
}

extern "C" int setsockopt(int fd, int level, int option, const void* valuep, socklen_t size)
#if defined(__GLIBC__)
    noexcept
#endif
{
#if !defined(MSG_NOSIGNAL) && defined(SO_NOSIGPIPE)
    if (level == SOL_SOCKET && option == SO_NOSIGPIPE && faultMode() == "sockopt"
        && !s_setupFaults) {
        ++s_setupFaults;
        errno = EINVAL;
        return -1;
    }
#endif
    using OptionFn = int (*)(int, int, int, const void*, socklen_t);
    static const OptionFn s_fnp = reinterpret_cast<OptionFn>(dlsym(RTLD_NEXT, "setsockopt"));
    if (!s_fnp) fail("Unable to forward setsockopt");
    return s_fnp(fd, level, option, valuep, size);
}
