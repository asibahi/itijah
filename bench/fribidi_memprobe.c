#include <stddef.h>
#include <stdint.h>

#include <stdatomic.h>

static atomic_uint_fast64_t g_alloc_count = 0;
static atomic_uint_fast64_t g_allocated_bytes = 0;
static atomic_uint_fast64_t g_current_bytes = 0;
static atomic_uint_fast64_t g_peak_bytes = 0;
static atomic_int g_enabled = 0;

static inline int probe_enabled(void) {
    return atomic_load_explicit(&g_enabled, memory_order_relaxed) != 0;
}

static inline void update_peak(uint64_t current) {
    uint64_t peak = atomic_load_explicit(&g_peak_bytes, memory_order_relaxed);
    while (current > peak &&
           !atomic_compare_exchange_weak_explicit(
               &g_peak_bytes, &peak, current, memory_order_relaxed, memory_order_relaxed)) {
    }
}

static inline void sub_current(size_t size) {
    uint64_t current = atomic_load_explicit(&g_current_bytes, memory_order_relaxed);
    while (1) {
        const uint64_t next = current > (uint64_t)size ? current - (uint64_t)size : 0;
        if (atomic_compare_exchange_weak_explicit(
                &g_current_bytes, &current, next, memory_order_relaxed, memory_order_relaxed)) {
            return;
        }
    }
}

static inline void on_alloc(size_t size) {
    if (!probe_enabled()) return;
    atomic_fetch_add_explicit(&g_alloc_count, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&g_allocated_bytes, (uint64_t)size, memory_order_relaxed);
    const uint64_t current =
        atomic_fetch_add_explicit(&g_current_bytes, (uint64_t)size, memory_order_relaxed) +
        (uint64_t)size;
    update_peak(current);
}

static inline void on_resize(size_t before, size_t after) {
    if (!probe_enabled()) return;
    atomic_fetch_add_explicit(&g_alloc_count, 1, memory_order_relaxed);
    if (after > before) {
        const size_t grow = after - before;
        atomic_fetch_add_explicit(&g_allocated_bytes, (uint64_t)grow, memory_order_relaxed);
        const uint64_t current =
            atomic_fetch_add_explicit(&g_current_bytes, (uint64_t)grow, memory_order_relaxed) +
            (uint64_t)grow;
        update_peak(current);
    } else if (before > after) {
        sub_current(before - after);
    }
}

static inline void on_free(size_t size) {
    if (!probe_enabled()) return;
    sub_current(size);
}

void itijah_fribidi_probe_begin(void) {
    atomic_store_explicit(&g_alloc_count, 0, memory_order_relaxed);
    atomic_store_explicit(&g_allocated_bytes, 0, memory_order_relaxed);
    atomic_store_explicit(&g_current_bytes, 0, memory_order_relaxed);
    atomic_store_explicit(&g_peak_bytes, 0, memory_order_relaxed);
    atomic_store_explicit(&g_enabled, 1, memory_order_relaxed);
}

void itijah_fribidi_probe_finish(uint64_t *alloc_count, uint64_t *allocated_bytes, uint64_t *peak_bytes) {
    atomic_store_explicit(&g_enabled, 0, memory_order_relaxed);
    if (alloc_count) *alloc_count = atomic_load_explicit(&g_alloc_count, memory_order_relaxed);
    if (allocated_bytes) *allocated_bytes = atomic_load_explicit(&g_allocated_bytes, memory_order_relaxed);
    if (peak_bytes) *peak_bytes = atomic_load_explicit(&g_peak_bytes, memory_order_relaxed);
}

#if defined(__APPLE__)

#include <dlfcn.h>
#include <malloc/malloc.h>
#include <pthread.h>
#include <stdlib.h>

typedef void *(*malloc_fn_t)(size_t);
typedef void (*free_fn_t)(void *);
typedef void *(*calloc_fn_t)(size_t, size_t);
typedef void *(*realloc_fn_t)(void *, size_t);
typedef int (*posix_memalign_fn_t)(void **, size_t, size_t);
typedef void *(*aligned_alloc_fn_t)(size_t, size_t);

static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static malloc_fn_t g_malloc = NULL;
static free_fn_t g_free = NULL;
static calloc_fn_t g_calloc = NULL;
static realloc_fn_t g_realloc = NULL;
static posix_memalign_fn_t g_posix_memalign = NULL;
static aligned_alloc_fn_t g_aligned_alloc = NULL;

static void init_real_symbols(void) {
    g_malloc = (malloc_fn_t)dlsym(RTLD_NEXT, "malloc");
    g_free = (free_fn_t)dlsym(RTLD_NEXT, "free");
    g_calloc = (calloc_fn_t)dlsym(RTLD_NEXT, "calloc");
    g_realloc = (realloc_fn_t)dlsym(RTLD_NEXT, "realloc");
    g_posix_memalign = (posix_memalign_fn_t)dlsym(RTLD_NEXT, "posix_memalign");
    g_aligned_alloc = (aligned_alloc_fn_t)dlsym(RTLD_NEXT, "aligned_alloc");
}

static inline size_t ptr_size(const void *ptr) {
    if (!ptr) return 0;
    return malloc_size((void *)ptr);
}

int itijah_fribidi_probe_available(void) { return 1; }

void *itijah_probe_malloc(size_t size) {
    pthread_once(&g_once, init_real_symbols);
    if (!g_malloc) return NULL;
    void *ptr = g_malloc(size);
    on_alloc(ptr_size(ptr));
    return ptr;
}

void itijah_probe_free(void *ptr) {
    pthread_once(&g_once, init_real_symbols);
    if (!g_free) return;
    const size_t before = ptr_size(ptr);
    g_free(ptr);
    on_free(before);
}

void *itijah_probe_calloc(size_t count, size_t size) {
    pthread_once(&g_once, init_real_symbols);
    if (!g_calloc) return NULL;
    void *ptr = g_calloc(count, size);
    on_alloc(ptr_size(ptr));
    return ptr;
}

void *itijah_probe_realloc(void *ptr, size_t size) {
    pthread_once(&g_once, init_real_symbols);
    if (!g_realloc) return NULL;
    const size_t before = ptr_size(ptr);
    void *out = g_realloc(ptr, size);
    if (out) on_resize(before, ptr_size(out));
    return out;
}

int itijah_probe_posix_memalign(void **memptr, size_t alignment, size_t size) {
    pthread_once(&g_once, init_real_symbols);
    if (!g_posix_memalign) return -1;
    const int rc = g_posix_memalign(memptr, alignment, size);
    if (rc == 0 && memptr && *memptr) on_alloc(ptr_size(*memptr));
    return rc;
}

void *itijah_probe_aligned_alloc(size_t alignment, size_t size) {
    pthread_once(&g_once, init_real_symbols);
    if (!g_aligned_alloc) return NULL;
    void *ptr = g_aligned_alloc(alignment, size);
    on_alloc(ptr_size(ptr));
    return ptr;
}

__attribute__((used)) static const struct {
    const void *replacement;
    const void *replacee;
} itijah_interpose[] __attribute__((section("__DATA,__interpose"))) = {
    { (const void *)itijah_probe_malloc, (const void *)malloc },
    { (const void *)itijah_probe_free, (const void *)free },
    { (const void *)itijah_probe_calloc, (const void *)calloc },
    { (const void *)itijah_probe_realloc, (const void *)realloc },
    { (const void *)itijah_probe_posix_memalign, (const void *)posix_memalign },
    { (const void *)itijah_probe_aligned_alloc, (const void *)aligned_alloc },
};

#elif defined(__linux__) && defined(__GLIBC__)

#include <malloc.h>
#include <stdlib.h>

extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void __libc_free(void *);

static inline size_t ptr_size(const void *ptr) {
    if (!ptr) return 0;
    return malloc_usable_size((void *)ptr);
}

int itijah_fribidi_probe_available(void) { return 1; }

void *malloc(size_t size) {
    void *ptr = __libc_malloc(size);
    on_alloc(ptr_size(ptr));
    return ptr;
}

void free(void *ptr) {
    const size_t before = ptr_size(ptr);
    __libc_free(ptr);
    on_free(before);
}

void *calloc(size_t count, size_t size) {
    void *ptr = __libc_calloc(count, size);
    on_alloc(ptr_size(ptr));
    return ptr;
}

void *realloc(void *ptr, size_t size) {
    const size_t before = ptr_size(ptr);
    void *out = __libc_realloc(ptr, size);
    if (out) on_resize(before, ptr_size(out));
    return out;
}

#else

int itijah_fribidi_probe_available(void) { return 0; }

#endif

